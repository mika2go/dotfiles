#!/usr/bin/env bash

read_cpu() {
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    local idle_total=$((idle + iowait))
    local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    printf '%s %s\n' "$idle_total" "$total"
}

read -r idle_a total_a < <(read_cpu)
sleep 0.12
read -r idle_b total_b < <(read_cpu)

total_delta=$((total_b - total_a))
idle_delta=$((idle_b - idle_a))
if (( total_delta > 0 )); then
    cpu=$((100 * (total_delta - idle_delta) / total_delta))
else
    cpu=0
fi

gpu_file="/sys/bus/pci/devices/0000:03:00.0/gpu_busy_percent"
gpu=0
if [[ -r "$gpu_file" ]]; then
    read -r gpu < "$gpu_file"
fi

memory_total="$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)"
memory_available="$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)"
if [[ -n "$memory_total" && -n "$memory_available" && "$memory_total" -gt 0 ]]; then
    memory=$((100 * (memory_total - memory_available) / memory_total))
else
    memory=0
fi

network=0
if nmcli -t -f STATE general 2>/dev/null | grep -qx connected; then
    network=1
fi

volume_line="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)"
volume="$(awk '{ printf "%d", $2 * 100 }' <<< "$volume_line")"
[[ -n "$volume" ]] || volume=0
muted=0
[[ "$volume_line" == *MUTED* ]] && muted=1

microphone_line="$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)"
microphone="$(awk '{ printf "%d", $2 * 100 }' <<< "$microphone_line")"
[[ -n "$microphone" ]] || microphone=0

printf '%s|%s|%s|%s|%s|%s|%s\n' \
    "$cpu" "$gpu" "$memory" "$network" "$volume" "$muted" "$microphone"
