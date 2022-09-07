#!/bin/bash
set -eu

ETH=$(grep 000e /sys/class/net/*/device/subsystem_device | awk -F"/" '{print $5}' | head -n 1)

echo 0 2 > /sys/class/net/$ETH/device/ptp/ptp*/pins/U.FL2
echo 0 1 > /sys/class/net/$ETH/device/ptp/ptp*/pins/U.FL1
echo 0 2 > /sys/class/net/$ETH/device/ptp/ptp*/pins/SMA2
echo 0 1 > /sys/class/net/$ETH/device/ptp/ptp*/pins/SMA1

echo "Disabled all SMA and U.FL Connections"
