#!/system/bin/sh
MODDIR=${0%/*}

# Wait for boot completion
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

# Enforce PCIe combo chip power on to prevent runtime PM glitches
for d in /sys/bus/pci/devices/*; do
    echo on > "$d/power/control" 2>/dev/null
done
echo on > /sys/devices/platform/soc/soc:bcmdhd_wlan/power/control 2>/dev/null
echo on > /sys/devices/platform/soc/1c00000.qcom,pcie/power/control 2>/dev/null
echo on > /sys/devices/platform/soc/1c10000.qcom,pcie/power/control 2>/dev/null

# Enforce bluesleep LPM 0
if [ -e /proc/bluetooth/sleep/lpm ]; then
    echo 0 > /proc/bluetooth/sleep/lpm 2>/dev/null
fi

# Apply APEX bind mounts in init namespace
for APEX_DIR in /apex/com.android.bt /apex/com.android.bt@361099999; do
    if [ -d "$APEX_DIR" ]; then
        mount --bind "$MODDIR/libbluetooth_jni.so" "$APEX_DIR/lib64/libbluetooth_jni.so" 2>/dev/null
        mount --bind "$MODDIR/interop_database.conf" "$APEX_DIR/etc/bluetooth/interop_database.conf" 2>/dev/null
    fi
done

# Apply APEX bind mounts inside zygote namespaces
for ZPID in $(pidof zygote64 zygote); do
    if [ -n "$ZPID" ]; then
        for APEX_DIR in /apex/com.android.bt /apex/com.android.bt@361099999; do
            nsenter -t "$ZPID" -m -- mount --bind "$MODDIR/libbluetooth_jni.so" "$APEX_DIR/lib64/libbluetooth_jni.so" 2>/dev/null
            nsenter -t "$ZPID" -m -- mount --bind "$MODDIR/interop_database.conf" "$APEX_DIR/etc/bluetooth/interop_database.conf" 2>/dev/null
        done
    fi
done

# If com.android.bluetooth loaded the unpatched library before service.sh ran, restart it
BT_PID=$(pidof com.android.bluetooth)
if [ -n "$BT_PID" ]; then
    MOD_INODE=$(ls -i "$MODDIR/libbluetooth_jni.so" 2>/dev/null | awk '{print $1}')
    if [ -n "$MOD_INODE" ]; then
        if ! grep -q "$MOD_INODE" "/proc/$BT_PID/maps" 2>/dev/null; then
            kill -9 "$BT_PID"
        fi
    fi
fi

# Background watchdog to enforce stability parameters across BT restarts
(
    while true; do
        if [ -e /proc/bluetooth/sleep/lpm ]; then
            echo 0 > /proc/bluetooth/sleep/lpm 2>/dev/null
        fi
        for d in /sys/bus/pci/devices/*; do
            echo on > "$d/power/control" 2>/dev/null
        done
        echo on > /sys/devices/platform/soc/1c00000.qcom,pcie/power/control 2>/dev/null
        echo on > /sys/devices/platform/soc/1c10000.qcom,pcie/power/control 2>/dev/null
        sleep 30
    done
) &
