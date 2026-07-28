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
if ((total_delta > 0)); then
    cpu=$((100 * (total_delta - idle_delta) / total_delta))
else
    cpu=0
fi

gpu=0
gpu_file="/sys/bus/pci/devices/0000:03:00.0/gpu_busy_percent"
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

temperature=0
for sensor in /sys/class/hwmon/hwmon*/temp*_input; do
    [[ -r "$sensor" ]] || continue
    read -r raw < "$sensor"
    value=$((raw / 1000))
    if ((value >= 15 && value <= 120 && value > temperature)); then
        temperature=$value
    fi
done

disk="$(df -P /home 2>/dev/null | awk 'NR == 2 { gsub("%", "", $5); print $5 }')"
[[ -n "$disk" ]] || disk=0

source_line="$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)"
microphone="$(awk '{ printf "%d", $2 * 100 }' <<< "$source_line")"
[[ -n "$microphone" ]] || microphone=0

printf '%s|%s|%s|%s|%s|%s\n' \
    "$cpu" "$gpu" "$memory" "$temperature" "$disk" "$microphone"
