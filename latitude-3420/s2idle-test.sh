#!/usr/bin/env bash
# s2idle (S0ix) validation script for Intel laptops on Arch Linux
# Requirements: bash, sudo, dmesg, journalctl, grep, awk, tee
# Optional (if available): intel_pmc_core driver (CONFIG_INTEL_PMC_CORE), turbostat, powertop

set -euo pipefail

log() { echo "[s2idle-test] $*" | tee -a "$LOGFILE"; }
die() { echo "[s2idle-test][ERROR] $*" | tee -a "$LOGFILE" >&2; exit 1; }

# Setup
TS="$(date +%Y%m%d_%H%M%S)"
OUTDIR="${OUTDIR:-$HOME/s2idle_test_$TS}"
mkdir -p "$OUTDIR"
LOGFILE="$OUTDIR/run.log"
exec > >(tee -a "$LOGFILE") 2>&1

log "Output directory: $OUTDIR"
log "Kernel: $(uname -a)"
log "User: $(whoami)"

if [[ $EUID -ne 0 ]]; then
  die "Please run as root (sudo) to access required sysfs and suspend operations."
fi

# Helpers
read_file() { [[ -r "$1" ]] && cat "$1" || echo "NA"; }
has_mod() { lsmod | awk '{print $1}' | grep -qx "$1"; }

# 1) Basic platform checks
log "=== Platform checks ==="
CPU_VENDOR="$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')"
log "CPU vendor: ${CPU_VENDOR:-unknown}"
if [[ "${CPU_VENDOR:-}" != "GenuineIntel" ]]; then
  log "Warning: Non-Intel CPU reported; S0ix validation may not apply."
fi

# 2) Suspend mode capabilities
log "=== Suspend capabilities ==="
SUSPEND_MODES_FILE="/sys/power/mem_sleep"
if [[ ! -f "$SUSPEND_MODES_FILE" ]]; then
  die "Missing $SUSPEND_MODES_FILE. systemd/kernel may not support mem sleep selection."
fi
log "Current mem_sleep: $(read_file $SUSPEND_MODES_FILE)"
# mem_sleep shows e.g.: s2idle [deep] or [s2idle] deep
if ! grep -qw "s2idle" "$SUSPEND_MODES_FILE"; then
  die "s2idle not listed in $SUSPEND_MODES_FILE. Firmware or kernel may not support S0ix."
fi

# 3) intel_pmc_core for S0ix residency
log "=== Intel PMC (S0ix) interface check ==="
PMC_DIR="/sys/kernel/debug/pmc_core"
if [[ ! -d "$PMC_DIR" ]]; then
  log "intel_pmc_core debugfs not present. Attempting to load module..."
  modprobe intel_pmc_core 2>/dev/null || true
fi
if [[ ! -d "$PMC_DIR" ]]; then
  log "Could not access ${PMC_DIR}. Ensure:"
  log " - intel_pmc_core is built/loaded"
  log " - debugfs is mounted (mount -t debugfs none /sys/kernel/debug)"
  log "Proceeding, but S0ix counters may be unavailable."
fi

# 4) Optional tools
HAS_TURBOSTAT=0
if command -v turbostat >/dev/null 2>&1; then
  HAS_TURBOSTAT=1
  log "turbostat found (optional pre/post verification)."
else
  log "turbostat not found (optional). Install via: pacman -S turbostat (in linux-tools)."
fi

# 5) Prepare: force s2idle for this test only
log "=== Forcing s2idle for this test ==="
ORIG_MEM_SLEEP="$(read_file $SUSPEND_MODES_FILE)"
log "Original mem_sleep: $ORIG_MEM_SLEEP"
log "Setting mem_sleep to s2idle for test..."
echo s2idle > "$SUSPEND_MODES_FILE" || die "Failed to set s2idle in $SUSPEND_MODES_FILE"

# 6) Collect baseline metrics
log "=== Baseline metrics (before suspend) ==="
# PMC residency
if [[ -d "$PMC_DIR" ]]; then
  log "-- PMC S0ix baseline --"
  PMC_BEFORE="$OUTDIR/pmc_before.txt"
  cat "$PMC_DIR/slp_s0_residency_usec" 2>/dev/null | tee "$OUTDIR/slp_s0_residency_usec_before.txt" || true
  # pmc_core exposes 'slp_s0_residency_usec' and sometimes 's0ix_residency_usec'
  for f in slp_s0_residency_usec slp_s0_residency_ms s0ix_residency_usec s0ix_residency_ms; do
    [[ -f "$PMC_DIR/$f" ]] && echo "$f=$(cat "$PMC_DIR/$f")" | tee -a "$PMC_BEFORE"
  done
  # Fallback consolidated dump if available
  for dump in "pkgc_state_show" "counters" "constraints"; do
    [[ -f "$PMC_DIR/$dump" ]] && { echo "===== $dump =====" | tee -a "$PMC_BEFORE"; cat "$PMC_DIR/$dump" | tee -a "$PMC_BEFORE"; }
  done
else
  log "Skipping PMC baseline (unavailable)."
fi

# GPU RC6 residency (i915 power saving)
I915_DIR="/sys/class/drm/card0"
if [[ -f "$I915_DIR/device/power/runtime_status" ]]; then
  log "-- Intel GPU runtime status (before) --"
  cat "$I915_DIR/device/power/runtime_status" | tee "$OUTDIR/i915_runtime_status_before.txt" || true
fi
if [[ -f "$I915_DIR/gt/rc6_residency_ms" ]]; then
  log "-- Intel GPU RC6 residency (before) --"
  cat "$I915_DIR/gt/rc6_residency_ms" | tee "$OUTDIR/i915_rc6_before.txt" || true
fi

# turbostat baseline (short sample)
if [[ $HAS_TURBOSTAT -eq 1 ]]; then
  log "-- turbostat baseline (3s) --"
  turbostat --quiet --Summary --interval 1 --iterations 3 2>/dev/null | tee "$OUTDIR/turbostat_before.txt" || true
fi

# powertop baseline summary, if available
if command -v powertop >/dev/null 2>&1; then
  log "-- powertop baseline (1 sample) --"
  powertop --time=3 --html="$OUTDIR/powertop_before.html" >/dev/null 2>&1 || true
  log "Powertop HTML report saved."
fi

# 7) Capture dmesg/journal before suspend
log "=== Capturing logs before suspend ==="
dmesg -T | tail -n 300 > "$OUTDIR/dmesg_before.txt" || true
journalctl -k -b > "$OUTDIR/journal_kernel_boot.txt" || true

# 8) Suspend test
SUSPEND_SECONDS="${SUSPEND_SECONDS:-20}"
log "=== Test suspend: s2idle for ${SUSPEND_SECONDS}s ==="
log "Disconnect external USB dongles and network cables if possible for best S0ix."
log "Suspending in 5 seconds... Press power button or open lid to resume."
sleep 5

# Mark time
BEFORE_EPOCH="$(date +%s)"
systemctl suspend || die "systemctl suspend failed"
AFTER_EPOCH="$(date +%s)"
SLEPT="$((AFTER_EPOCH - BEFORE_EPOCH))"
log "System resumed. Elapsed wall time: ${SLEPT}s"

# 9) Post-suspend metrics
log "=== Post-suspend metrics ==="
if [[ -d "$PMC_DIR" ]]; then
  log "-- PMC S0ix after --"
  PMC_AFTER="$OUTDIR/pmc_after.txt"
  for f in slp_s0_residency_usec slp_s0_residency_ms s0ix_residency_usec s0ix_residency_ms; do
    [[ -f "$PMC_DIR/$f" ]] && echo "$f=$(cat "$PMC_DIR/$f")" | tee -a "$PMC_AFTER"
  done
  for dump in "pkgc_state_show" "counters" "constraints"; do
    [[ -f "$PMC_DIR/$dump" ]] && { echo "===== $dump =====" | tee -a "$PMC_AFTER"; cat "$PMC_DIR/$dump" | tee -a "$PMC_AFTER"; }
  done
fi

if [[ -f "$I915_DIR/device/power/runtime_status" ]]; then
  log "-- Intel GPU runtime status (after) --"
  cat "$I915_DIR/device/power/runtime_status" | tee "$OUTDIR/i915_runtime_status_after.txt" || true
fi
if [[ -f "$I915_DIR/gt/rc6_residency_ms" ]]; then
  log "-- Intel GPU RC6 residency (after) --"
  cat "$I915_DIR/gt/rc6_residency_ms" | tee "$OUTDIR/i915_rc6_after.txt" || true
fi

if [[ $HAS_TURBOSTAT -eq 1 ]]; then
  log "-- turbostat after (3s) --"
  turbostat --quiet --Summary --interval 1 --iterations 3 2>/dev/null | tee "$OUTDIR/turbostat_after.txt" || true
fi

if command -v powertop >/dev/null 2>&1; then
  log "-- powertop after (1 sample) --"
  powertop --time=3 --html="$OUTDIR/powertop_after.html" >/dev/null 2>&1 || true
fi

# 10) Evaluate S0ix delta
log "=== Evaluating S0ix residency delta ==="
parse_val() {
  local file="$1"
  local key="$2"
  awk -F'[= ]' -v k="$key" '$1 ~ k {print $2}' "$file" 2>/dev/null || true
}

S0IX_BEFORE_USEC=""
S0IX_AFTER_USEC=""
if [[ -f "$PMC_BEFORE" && -f "$PMC_AFTER" ]]; then
  # Prefer slp_s0_residency_usec; fallback to s0ix_residency_usec or ms versions
  for k in slp_s0_residency_usec s0ix_residency_usec; do
    S0IX_BEFORE_USEC="$(parse_val "$PMC_BEFORE" "$k")"
    S0IX_AFTER_USEC="$(parse_val "$PMC_AFTER" "$k")"
    [[ -n "${S0IX_BEFORE_USEC:-}" && -n "${S0IX_AFTER_USEC:-}" ]] && break
  done
  if [[ -z "${S0IX_BEFORE_USEC:-}" || -z "${S0IX_AFTER_USEC:-}" ]]; then
    # try ms variants and convert
    for k in slp_s0_residency_ms s0ix_residency_ms; do
      local_b="$(parse_val "$PMC_BEFORE" "$k")"
      local_a="$(parse_val "$PMC_AFTER" "$k")"
      if [[ -n "${local_b:-}" && -n "${local_a:-}" ]]; then
        S0IX_BEFORE_USEC="$((local_b * 1000))"
        S0IX_AFTER_USEC="$((local_a * 1000))"
        break
      fi
    done
  fi
fi

STATUS="UNKNOWN"
if [[ -n "${S0IX_BEFORE_USEC:-}" && -n "${S0IX_AFTER_USEC:-}" ]]; then
  DELTA_USEC=$((S0IX_AFTER_USEC - S0IX_BEFORE_USEC))
  log "S0ix residency delta (usec): ${DELTA_USEC}"
  # If system actually suspended for ~20s, we expect a noticeable increase.
  if (( DELTA_USEC > 3_000_000 )); then
    STATUS="PASS"
  else
    STATUS="FAIL"
  fi
else
  log "Could not compute S0ix delta (missing counters)."
  STATUS="INCONCLUSIVE"
fi

# 11) Collect relevant logs after suspend
log "=== Logs after suspend ==="
dmesg -T | tail -n 500 > "$OUTDIR/dmesg_after.txt" || true
journalctl --since "@$BEFORE_EPOCH" > "$OUTDIR/journal_since_before.txt" || true

# 12) Restore original mem_sleep
log "=== Restoring original mem_sleep ==="
if [[ -n "${ORIG_MEM_SLEEP:-}" ]]; then
  # Restore the bracketed default by writing the token without brackets
  if echo "$ORIG_MEM_SLEEP" | grep -q '\[s2idle\]'; then
    echo s2idle > "$SUSPEND_MODES_FILE" || true
  elif echo "$ORIG_MEM_SLEEP" | grep -q '\[deep\]'; then
    echo deep > "$SUSPEND_MODES_FILE" || true
  else
    # Fallback: set to deep, the safer default for many systems
    echo deep > "$SUSPEND_MODES_FILE" || true
  fi
  log "mem_sleep now: $(read_file $SUSPEND_MODES_FILE)"
fi

# 13) Summary and hints
log "=== Result: $STATUS ==="
case "$STATUS" in
  PASS)
    log "S2idle (S0ix) appears to be working: S0ix residency increased during suspend."
    ;;
  FAIL)
    log "S2idle did not accumulate residency as expected."
    log "Hints to improve:"
    log "- Ensure BIOS/UEFI is up to date and Intel Modern Standby/S0ix is supported/enabled."
    log "- Unplug USB dongles and disable problematic wake sources (USB, BT) temporarily."
    log "- Stop apps causing timers/interrupts; check powertop 'Tunables' and 'Device stats'."
    log "- Verify iGPU runtime PM: see $OUTDIR/i915_runtime_status_before.txt and after."
    log "- Try kernel cmdline tweaks: mem_sleep_default=s2idle, pcie_aspm=force,"
    log "  intel_idle.max_cstate=9, i915.enable_dc=2, i915.enable_psr=1 (be cautious and test)."
    log "- Check $OUTDIR/dmesg_after.txt and $OUTDIR/journal_since_before.txt for suspend blockers."
    ;;
  INCONCLUSIVE)
    log "Could not verify via PMC counters."
    log "Ensure intel_pmc_core and debugfs are available: "
    log "  modprobe intel_pmc_core; mount -t debugfs none /sys/kernel/debug"
    log "Re-run the script after enabling those."
    ;;
esac

log "All artifacts saved in: $OUTDIR"
