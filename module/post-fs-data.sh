#!/system/bin/sh
MODDIR=${0%/*}

# Disable UART low power sleep mode
if [ -e /proc/bluetooth/sleep/lpm ]; then
    echo 0 > /proc/bluetooth/sleep/lpm
fi

# Ensure /data/misc/bluedroid/interop_database_dynamic.conf exists with proper entries
if [ ! -f /data/misc/bluedroid/interop_database_dynamic.conf ]; then
    cp "$MODDIR/interop_database.conf" /data/misc/bluedroid/interop_database_dynamic.conf
    chown bluetooth:bluetooth /data/misc/bluedroid/interop_database_dynamic.conf
    chmod 660 /data/misc/bluedroid/interop_database_dynamic.conf
fi

# Bind mount patched files if APEX is already mounted in init namespace
for APEX_DIR in /apex/com.android.bt /apex/com.android.bt@361099999; do
    if [ -d "$APEX_DIR" ]; then
        mount --bind "$MODDIR/libbluetooth_jni.so" "$APEX_DIR/lib64/libbluetooth_jni.so" 2>/dev/null
        mount --bind "$MODDIR/interop_database.conf" "$APEX_DIR/etc/bluetooth/interop_database.conf" 2>/dev/null
    fi
done

# Apply system properties for A2DP software encoding pipeline & Samsung capability overrides
/data/adb/ksud resetprop -n -p persist.bluetooth.a2dp_offload.disabled true
/data/adb/ksud resetprop -n -p persist.bluetooth.a2dp_offload.cap none
/data/adb/ksud resetprop -n -p persist.bluetooth.samsung.a2dp_offload.cap none
/data/adb/ksud resetprop -n -p persist.vendor.qcom.bluetooth.enable.splita2dp false
/data/adb/ksud resetprop -n -p persist.vendor.qcom.bluetooth.a2dp_offload_cap none
/data/adb/ksud resetprop -n -p vendor.audio.feature.a2dp_offload.enable false
/data/adb/ksud resetprop -n -p ro.bluetooth.a2dp_offload.supported false

# HCI timeouts & multi-transport interop
/data/adb/ksud resetprop -n bluetooth.hci.timeout_milliseconds 60000
/data/adb/ksud resetprop -n bluetooth.hci.restart_timeout_milliseconds 60000
/data/adb/ksud resetprop -n ro.hw_timeout_multiplier 3
/data/adb/ksud resetprop -n persist.bluetooth.sniff_offload.enabled false
