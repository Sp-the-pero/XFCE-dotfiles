#!/usr/bin/env bash
#
# system-monitor-genmon.sh
# A clean CPU / RAM / Storage monitor for the XFCE Generic Monitor (genmon) plugin.
# Auto-adjusts layout: single-line for Horizontal panels, stacked for Vertical/Deskbar panels.
# Built for EndeavourOS / Arch-based systems.
#
# INSTALL:
#   chmod +x system-monitor-genmon.sh
#   Then in XFCE: right-click panel -> Panel -> Add New Items -> Generic Monitor
#   Set "Command" to the full path of this script, e.g.:
#     /home/YOURUSER/.config/xfce4/genmon/system-monitor-genmon.sh
#   Set "Period" to 1 (second).
#
# NOTE on storage: by default this checks the root partition "/".
# Change ROOT_MOUNT below if you want a different mount point (e.g. /home).

ROOT_MOUNT="/"
CACHE_FILE="/tmp/.genmon_cpu_prev"

# ---------- DETECT PANEL ORIENTATION ----------
# xfce4-panel stores each panel's layout mode in xfconf:
#   0 = Horizontal, 1 = Vertical, 2 = Deskbar
# We scan all configured panels and grab the first "mode" value found.
# If detection fails for any reason, we default to Horizontal (0) so the
# widget always still displays something sensible.
panel_mode=$(xfconf-query -c xfce4-panel -l -v 2>/dev/null \
             | grep -m1 -E '/panels/panel-[0-9]+/mode' \
             | awk '{print $NF}')
panel_mode="${panel_mode:-0}"

# ---------- CPU USAGE (delta-based, accurate) ----------
read -r cpu_line < /proc/stat
read -r _ user nice system idle iowait irq softirq steal _ <<< "$cpu_line"

prev_total=0
prev_idle=0
if [[ -f "$CACHE_FILE" ]]; then
    read -r prev_total prev_idle < "$CACHE_FILE"
fi

idle_all=$((idle + iowait))
non_idle=$((user + nice + system + irq + softirq + steal))
total=$((idle_all + non_idle))

diff_total=$((total - prev_total))
diff_idle=$((idle_all - prev_idle))

if [[ $diff_total -gt 0 ]]; then
    cpu_pct=$(( (100 * (diff_total - diff_idle)) / diff_total ))
else
    cpu_pct=0
fi

echo "$total $idle_all" > "$CACHE_FILE"

# ---------- RAM USAGE ----------
read -r mem_total mem_used <<< "$(free -m | awk '/^Mem:/ {print $2, $3}')"
if [[ "$mem_total" -gt 0 ]]; then
    ram_pct=$(( 100 * mem_used / mem_total ))
else
    ram_pct=0
fi

# ---------- STORAGE USAGE ----------
disk_pct=$(df --output=pcent "$ROOT_MOUNT" | tail -1 | tr -dc '0-9')
disk_used_h=$(df -h --output=used "$ROOT_MOUNT" | tail -1 | tr -d ' ')
disk_size_h=$(df -h --output=size "$ROOT_MOUNT" | tail -1 | tr -d ' ')

# ---------- COLOR THRESHOLDS ----------
color_for() {
    local pct=$1
    if   [[ $pct -ge 85 ]]; then echo "#e06c75"   # red
    elif [[ $pct -ge 60 ]]; then echo "#e5c07b"   # yellow
    else echo "#98c379"                            # green
    fi
}

cpu_color=$(color_for "$cpu_pct")
ram_color=$(color_for "$ram_pct")
disk_color=$(color_for "$disk_pct")

# ---------- BUILD OUTPUT (layout depends on panel orientation) ----------
# NOTE: If you have a Nerd Font installed (e.g. "JetBrainsMono Nerd Font"),
# you can swap the labels below (CPU / RAM / DSK) for icon glyphs like
# 󰻠  (cpu) 󰍛  (ram) 󰋊  (disk) for a slicker look. Plain labels are used
# here so the widget works correctly on any font, out of the box.

cpu_part="<span color='#61afef'>CPU</span>"
cpu_output="<span color='${cpu_color}'>${cpu_pct}%</span>"
ram_part="<span color='#61afef'>RAM</span>"
ram_output="<span color='${ram_color}'>${ram_pct}%</span>"
disk_part="<span color='#61afef'>DSK</span>"
disk_output="<span color='${disk_color}'>${disk_pct}%</span>"

if [[ "$panel_mode" == "0" ]]; then
    # Horizontal panel: single line, double-space separated
    txt="${cpu_part} ${cpu_output}  ${ram_part} ${ram_output}  ${disk_part} ${disk_output}"
else
    # Vertical / Deskbar panel: stacked, one metric per line
    txt="${cpu_part}\n${cpu_output}\n------\n${ram_part}\n${ram_output}\n------\n${disk_part}\n${disk_output}"
fi

echo -e "<txt>${txt}</txt>"

echo "<tool>CPU: ${cpu_pct}%
RAM: ${mem_used}MB / ${mem_total}MB (${ram_pct}%)
Storage (${ROOT_MOUNT}): ${disk_used_h} / ${disk_size_h} (${disk_pct}%)</tool>"

echo "<click>xfce4-taskmanager</click>"