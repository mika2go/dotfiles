#!/usr/bin/env bash

gpu_device="/sys/bus/pci/devices/0000:03:00.0"
usage_file="${gpu_device}/gpu_busy_percent"

usage="0"
if [ -r "$usage_file" ]; then
    read -r usage < "$usage_file"
fi

temperature="?"
for temperature_file in "${gpu_device}"/hwmon/hwmon*/temp1_input; do
    if [ -r "$temperature_file" ]; then
        read -r temperature_raw < "$temperature_file"
        temperature=$((temperature_raw / 1000))
        break
    fi
done

printf '{"text":"%s","tooltip":"GPU %s%%\\n%s°C"}\n' "$usage" "$usage" "$temperature"
