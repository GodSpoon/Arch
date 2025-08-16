#!/usr/bin/env bash
set -euo pipefail

need_sudo() {
  if [[ $EUID -ne 0 ]]; then
    echo "sudo -n true >/dev/null 2>&1" | bash || {
      echo "Note: some checks may prompt for sudo."
    }
  fi
}
need_sudo

hdr() { printf "\n=== %s ===\n" "$1"; }
row() { printf " - %-28s | Current: %-32s | Recommended: %s\n" "$1" "$2" "$3"; }
val() { [[ -n "${1:-}" ]] && echo "$1" || echo "N/A"; }

unit_active() {
  systemctl is-active "$1" 2>/dev/null || true
}
unit_enabled() {
  systemctl is-enabled "$1" 2>/dev/null || true
}
has_cmd() { command -v "$1" >/dev/null 2>&1; }

get_kernel_cmdline() {
  tr ' ' '\n' < /proc/cmdline 2>/dev/null | sed '/^$/d' | paste -sd' ' -
}

get_tlp_conf_val() {
  # Read effective value from tlp-stat -c if available; else parse /etc/tlp.conf fallback.
  local key="$1"
  if has_cmd tlp-stat; then
    sudo tlp-stat -c 2>/dev/null | awk -v k="^${key}=" '$0 ~ k {print $0; exit}' | cut -d= -f2-
  else
    awk -v k="^\\s*${key}\\s*=" '$0 ~ k && $1 !~ /^#/ {sub(/^.*=/,""); gsub(/[ \t]+$/,""); print; exit}' /etc/tlp.conf 2>/dev/null
  fi
}

get_sysfs() {
  local path="$1"
  [[ -r "$path" ]] && tr -d '\n' < "$path" || echo ""
}

hdr "Services and Core Tools"
tlp_active=$(unit_active tlp.service)
tlp_enabled=$(unit_enabled tlp.service)
ppd_active=$(unit_active power-profiles-daemon.service)
ppd_enabled=$(unit_enabled power-profiles-daemon.service)
nm_disp_enabled=$(unit_enabled NetworkManager-dispatcher.service)
rfkill_active=$(unit_active systemd-rfkill.service)
rfkill_socket=$(unit_active systemd-rfkill.socket)
powertop_service=$(unit_enabled powertop.service)
thermald_active=$(unit_active thermald.service)
thermald_enabled=$(unit_enabled thermald.service)

row "TLP service (active/enabled)" "$(val "$tlp_active/$tlp_enabled")" "active/enabled (primary PM)"
row "power-profiles-daemon" "$(val "$ppd_active/$ppd_enabled")" "inactive/disabled when using TLP"
row "NM dispatcher (for tlp-rdw)" "$(val "$nm_disp_enabled")" "enabled if using tlp-rdw"
row "systemd-rfkill (svc/socket)" "$(val "$rfkill_active/$rfkill_socket")" "masked when using TLP"
row "powertop.service" "$(val "$powertop_service")" "enabled (optional autotune at boot)"
row "thermald (active/enabled)" "$(val "$thermald_active/$thermald_enabled")" "active/enabled (recommended)"

hdr "CPU Policy and Profiles"
gov_cur=""
if has_cmd cpupower; then
  gov_cur=$(cpupower frequency-info 2>/dev/null | awk -F': ' '/current policy/ {print $2}')
fi
: "${gov_cur:=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true)}"
row "CPU governor" "$(val "$gov_cur")" "performance (AC), balance_power/powersave (BAT)"

epp_path="/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"
epp_cur=$(get_sysfs "$epp_path")
row "Energy Perf Preference" "$(val "$epp_cur")" "performance (AC), power (BAT)"

platform_profile_path="/sys/firmware/acpi/platform_profile"
platform_profile_cur=$(get_sysfs "$platform_profile_path")
row "Platform profile" "$(val "$platform_profile_cur")" "performance/balanced (AC), low-power (BAT)"

boost_cur=$(get_sysfs "/sys/devices/system/cpu/cpufreq/boost")
[[ -z "$boost_cur" ]] && boost_cur=$(get_sysfs "/sys/devices/system/cpu/intel_pstate/no_turbo")
[[ "$boost_cur" == "1" ]] && boost_cur="enabled"
[[ "$boost_cur" == "0" ]] && boost_cur="disabled"
row "CPU Turbo/Boost" "$(val "$boost_cur")" "on (AC), off (BAT) for battery-life mode"

hdr "Intel Graphics (i915)"
mod_i915_params=""
if [[ -r /sys/module/i915/parameters/enable_fbc ]]; then
  fbc=$(get_sysfs /sys/module/i915/parameters/enable_fbc)
  mod_i915_params+="enable_fbc=$fbc "
fi
if [[ -r /sys/module/i915/parameters/enable_psr ]]; then
  psr=$(get_sysfs /sys/module/i915/parameters/enable_psr)
  mod_i915_params+="enable_psr=$psr "
fi
if [[ -r /sys/module/i915/parameters/enable_rc6 ]]; then
  rc6=$(get_sysfs /sys/module/i915/parameters/enable_rc6)
  mod_i915_params+="enable_rc6=$rc6 "
fi
row "i915 params (runtime)" "$(val "$mod_i915_params")" "enable_fbc=1, enable_psr=1, enable_rc6=1 (via modprobe.d)"

# Optional: current GPU freq limits if available
gpu_min=$(get_sysfs /sys/class/drm/card0/gt_min_freq_mhz)
gpu_max=$(get_sysfs /sys/class/drm/card0/gt_max_freq_mhz)
gpu_cur=$(get_sysfs /sys/class/drm/card0/gt_cur_freq_mhz)
row "Intel GPU freq (min/cur/max)" "$(val "${gpu_min:-?}/${gpu_cur:-?}/${gpu_max:-?}")" "lower max on BAT for battery-life mode"

hdr "TLP Configuration Highlights"
tlp_present="no"
has_cmd tlp-stat && tlp_present="yes"
row "TLP installed" "$tlp_present" "yes"

tlp_default_mode=$(get_tlp_conf_val TLP_DEFAULT_MODE)
row "TLP default mode" "$(val "$tlp_default_mode")" "BAT (optional), or leave default"

cpu_gov_ac=$(get_tlp_conf_val CPU_SCALING_GOVERNOR_ON_AC)
cpu_gov_bat=$(get_tlp_conf_val CPU_SCALING_GOVERNOR_ON_BAT)
row "TLP CPU gov (AC/BAT)" "$(val "${cpu_gov_ac}/${cpu_gov_bat}")" "performance or balance_performance (AC) / balance_power or powersave (BAT)"

epp_ac=$(get_tlp_conf_val CPU_ENERGY_PERF_POLICY_ON_AC)
epp_bat=$(get_tlp_conf_val CPU_ENERGY_PERF_POLICY_ON_BAT)
row "TLP EPP (AC/BAT)" "$(val "${epp_ac}/${epp_bat}")" "performance/balance_performance (AC) / power (BAT)"

pp_ac=$(get_tlp_conf_val PLATFORM_PROFILE_ON_AC)
pp_bat=$(get_tlp_conf_val PLATFORM_PROFILE_ON_BAT)
row "TLP platform profile" "$(val "${pp_ac}/${pp_bat}")" "performance/balanced (AC) / low-power (BAT)"

boost_ac=$(get_tlp_conf_val CPU_BOOST_ON_AC)
boost_bat=$(get_tlp_conf_val CPU_BOOST_ON_BAT)
row "TLP CPU boost (AC/BAT)" "$(val "${boost_ac}/${boost_bat}")" "1 on AC / 0 on BAT for battery-life"

wifi_ac=$(get_tlp_conf_val WIFI_PWR_ON_AC)
wifi_bat=$(get_tlp_conf_val WIFI_PWR_ON_BAT)
row "TLP Wi-Fi PM (AC/BAT)" "$(val "${wifi_ac}/${wifi_bat}")" "off on AC / on on BAT"

usb_auto=$(get_tlp_conf_val USB_AUTOSUSPEND)
row "TLP USB autosuspend" "$(val "$usb_auto")" "1 (with per-device blacklist if needed)"

start_thresh=$(get_tlp_conf_val START_CHARGE_THRESH_BAT0)
stop_thresh=$(get_tlp_conf_val STOP_CHARGE_THRESH_BAT0)
row "Battery charge thresholds" "$(val "${start_thresh}/${stop_thresh}")" "e.g., 75/80 if supported"

hdr "Sleep / Hibernate"
sleep_cfg="/etc/systemd/sleep.conf"
allow_suspend=$(grep -E '^\s*AllowSuspend' "$sleep_cfg" 2>/dev/null | tail -n1 | awk -F= '{print $2}' | tr -d ' ')
allow_hib=$(grep -E '^\s*AllowHibernation' "$sleep_cfg" 2>/dev/null | tail -n1 | awk -F= '{print $2}' | tr -d ' ')
allow_sth=$(grep -E '^\s*AllowSuspendThenHibernate' "$sleep_cfg" 2>/dev/null | tail -n1 | awk -F= '{print $2}' | tr -d ' ')
suspend_state=$(grep -E '^\s*SuspendState' "$sleep_cfg" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d ' ')
hibernate_mode=$(grep -E '^\s*HibernateMode' "$sleep_cfg" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d ' ')
hibernate_state=$(grep -E '^\s*HibernateState' "$sleep_cfg" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d ' ')
row "Allow Suspend/Hibernate" "$(val "${allow_suspend:-default}/${allow_hib:-default}")" "yes/yes"
row "Suspend-then-Hibernate" "$(val "${allow_sth:-default}")" "yes (optional)"
row "SuspendState" "$(val "${suspend_state:-kernel default}")" "mem"
row "HibernateMode/State" "$(val "${hibernate_mode:-default}/${hibernate_state:-default}")" "platform shutdown / disk"

mem_sleep=$(cat /sys/power/mem_sleep 2>/dev/null || true)
row "mem_sleep (runtime)" "$(val "$mem_sleep")" "deep preferred"

hdr "Kernel Parameters (cmdline)"
cmdline=$(get_kernel_cmdline)
row "Cmdline contains" "$(val "$cmdline")" "Consider: intel_idle.max_cstate=1, i915.enable_dc=0, mem_sleep_default=deep (only if needed)"

hdr "Networking Power Management"
wifi_dev=$(iw dev 2>/dev/null | awk '/Interface/ {print $2; exit}')
wifi_pm="N/A"
if [[ -n "${wifi_dev:-}" ]]; then
  wifi_pm=$(iw dev "$wifi_dev" get power_save 2>/dev/null | awk '{print $3}')
fi
row "Wi‑Fi power save (runtime)" "$(val "$wifi_pm")" "off (AC), on (BAT)"

bt_power="N/A"
if lsusb | grep -qi bluetooth; then
  bt_power="present (check TLP autosuspend/blacklist)"
fi
row "Bluetooth power mgmt" "$(val "$bt_power")" "autosuspend or disable when not needed"

hdr "Battery & Power Readouts"
bat="$(upower -e 2>/dev/null | grep -m1 BAT || true)"
if [[ -n "$bat" ]]; then
  cap=$(upower -i "$bat" 2>/dev/null | awk -F': *' '/energy-full:/ {print $2}')
  rate=$(upower -i "$bat" 2>/dev/null | awk -F': *' '/energy-rate:/ {print $2}')
  state=$(upower -i "$bat" 2>/dev/null | awk -F': *' '/state:/ {print $2}')
  row "Battery capacity (full)" "$(val "$cap")" "N/A"
  row "Battery rate / state" "$(val "${rate}/${state}")" "N/A"
else
  row "Battery (upower)" "not found" "N/A"
fi

hdr "Notes"
echo " - Recommended primary: TLP, with power-profiles-daemon disabled."
echo " - Use powertop for diagnostics; optional --auto-tune at boot."
echo " - For best battery: governors balance_power/powersave, EPP=power, boost off, platform low-power."
echo " - For best performance: governor performance, EPP=performance, boost on, platform performance."
echo " - Apply i915 power flags via /etc/modprobe.d/i915.conf if runtime shows they are off."
echo " - Configure sleep in /etc/systemd/sleep.conf; prefer deep (mem)."
echo " - Only add kernel params if troubleshooting specific sleep/power issues."
