# 🎧 Samsung Galaxy S20 Ultra — BCM4375 Bluetooth Disconnection & Audio Fix (v3.4)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Device: Galaxy S20 Ultra](https://img.shields.io/badge/Device-SM--G988N%20%7C%20z3q-blue.svg)](https://github.com/iamitgandhi/s20-ultra-5G_SM-G988N_Bluetooth-Disconnection-Fix)
[![Platform: KernelSU / Magisk / APatch](https://img.shields.io/badge/Root-KernelSU%20%7C%20Magisk%20%7C%20APatch-green.svg)](https://github.com/iamitgandhi/s20-ultra-5G_SM-G988N_Bluetooth-Disconnection-Fix)
[![ROM: UN1CA / OneUI Port / ArtisanROM](https://img.shields.io/badge/ROM-UN1CA%20%7C%20OneUI%207%2F8%20%7C%20ArtisanROM-orange.svg)](https://github.com/iamitgandhi/s20-ultra-5G_SM-G988N_Bluetooth-Disconnection-Fix)

A comprehensive, permanent engineering fix for severe Bluetooth instability, persistent peripheral disconnections (specifically **Galaxy Watch6 / Watch5 / Watch4**, **Galaxy Buds2 Pro**, and third-party speakers/soundbars like **Mivi Fort S200**), audio stutters, and relentless `com.android.bluetooth` daemon crashes on Samsung Galaxy S20 Ultra 5G (Snapdragon SM8250 / Broadcom BCM4375) running **UN1CA / ArtisanROM** (Android 15 / 16, OneUI 7 / 8 port) and custom ROMs.

---

## 📌 Problem Overview

Users running custom OneUI ports on Snapdragon 865 Samsung devices frequently encounter severe Bluetooth issues:
1. **Endless Watch Disconnect Loops:** Galaxy Watch (Watch6 Classic, Watch5, Watch4) disconnects every 30–60 seconds and continually reconnects.
2. **Audio Stutters & Music Dropouts:** Galaxy Buds2 Pro, soundbars, and car audio systems cut out or disconnect after 1–2 minutes of playback.
3. **Bluetooth Crashes When Scanning or Opening Settings:** Opening Bluetooth Settings or initiating pairing triggers an immediate daemon crash (`SIGABRT` / `SIGKILL`).
4. **Instant Sleep Suicide:** As soon as the screen is turned off or the phone goes idle, the entire Bluetooth stack terminates, dropping all active connections simultaneously.
5. **Relentless Daemon Restarts:** `dumpsys bluetooth_manager` reveals `Bluetooth crashed 130+ times` in just a few hours.

---

## 🔍 Root Cause Analysis (Deep Reverse Engineering)

Through live kernel tracing, tombstone analysis, and AArch64 disassembly of `/apex/com.android.bt/lib64/libbluetooth_jni.so`, **seven compounding root causes** were identified:

### 1. APCF Scan Filter Assertion Failure (`le_scanning_manager_impl.cc:1442`)
When Bluetooth Settings or system BLE services (`com.samsung.android.mcfserver`, `com.samsung.android.mcfds`) start scanning, they send vendor-specific advertising filters:
```
bluetooth: on_advertising_filter_complete: Got a Command complete LE_ADV_FILTER(0xfd57), status REPEATED_ATTEMPTS(0x17)
bluetooth: assert failed: complete_view.IsValid()
Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE) in tid (gd_stack_thread), pid (droid.bluetooth)
```
The Broadcom BCM4375 rejects repeated filter setup commands with status `0x17`. The returned packet contains no sub-fields, causing `complete_view.IsValid()` to return false. The stack then executed a fatal assertion (`vlog(FATAL)`), calling `__android_log_call_aborter` -> `abort()`, killing Bluetooth every time scanning occurred.

### 2. Connection Timeout Suicide (`classic_impl.h:352`)
When a classic Bluetooth ACL connection attempt timed out (e.g., if a paired device was powered off or temporarily out of range), Samsung's `on_create_connection_timeout` in `classic_impl.h` explicitly called `kill(getpid(), SIGKILL)`:
```
[classic_impl.h] on_create_connection_timeout for address: %s, so kill BT process
```
This suicide mechanism killed the entire Bluetooth daemon every 5 minutes whenever any background connection attempt failed.

### 3. HCI Watchdog Suicide Mechanisms (`hci_layer.cc` & 12 `kill()` sites)
The Google Gabeldorsche (GD) Bluetooth stack enforces strict HCI command timeout watchdogs (`abort_after_time_out`). Disassembly of `libbluetooth_jni.so` revealed **12 distinct `kill(getpid(), SIGKILL)` call sites** and `pthread_kill(thread, SIGABRT)` throughout the binary that deliberately killed the process on hardware events, timeouts, and AIDL status errors.

### 4. Unsupported `LE_ENERGY_INFO (0xfd59)` on Screen-Off
Whenever the screen turned off or the device entered doze, Android's `BatteryStats` dispatched vendor opcode `0xfd59` via `BTM_BleGetEnergyInfo` to query energy consumption. The Broadcom BCM4375 controller does not respond to `0xfd59` during low-power transitions. The command stalled, tripped the watchdog, and fired the SIGKILL suicide above.

### 5. Broadcom FullMAC Wi-Fi (`dhd`) PCIe Runtime PM RC0 Reset
Dmesg logs showed that the Wi-Fi PCIe link regularly entered idle suspend every 2–3 seconds:
```
dhdpcie_bus_suspend: Entering suspend state
msm_pcie_pm_suspend: RC0: PME_TURNOFF_MSG is sent out
msm_pcie_disable: PCIe: Assert the reset of endpoint of RC0.
```
Because the BCM4375 is a combo Wi-Fi/Bluetooth chip sharing internal power rails, asserting the PCIe reset on RC0 during bus suspend caused the Bluetooth UART core to temporarily stall or drop pending command responses.

### 6. Broadcom UART Low Power Mode (LPM) Framing Desync
Samsung's `bluesleep` driver had `/proc/bluetooth/sleep/lpm = 1`. During brief pauses, the UART line was put to sleep. When incoming packets arrived while clocks were waking up, bytes were dropped. The AOSP H4 packetizer logged `Unimplemented packet type <X>`, permanently losing byte framing.

### 7. Invalid Qualcomm Hastings Split-A2DP Offload
Generic Qualcomm build properties were present in the ROM (`persist.vendor.qcom.bluetooth.enable.splita2dp=true`, `ro.bluetooth.a2dp_offload.supported=true`). The Broadcom BCM4375 does **not** support Qualcomm Hexagon DSP Split A2DP over Slimbus. This caused 1,700+ buffer flushes in minutes, leading to audio stuttering and A2DP stream collapse.

---

## 🛠️ The Permanent Engineering Solution (v3.4)

This module provides a multi-layer solution packaged into a single flashable module:

### 1. Comprehensive Binary Patches in `libbluetooth_jni.so`
- **Neutralized All 12 `kill()` Suicide Call Sites:**
  NOP'd all 12 `bl kill@plt` calls (`0x3faf68`, `0x9d711c`, `0xab85dc`, `0xabe12c`, `0xac05fc`, `0xb92b04`, `0xb92bb0`, `0xb932a4`, `0xb935dc`, `0xb971bc`, `0xb973f4`, `0xb97588`) and `pthread_kill` (`0x3faf48`).
- **Bypassed Connection Timeout Suicide (`0x9d7108`):**
  Branched straight to function epilogue (`b 0x9d7120`), completely skipping `usleep` + `getpid` + `kill`.
- **Neutralized APCF `complete_view.IsValid()` Assertions in `on_advertising_filter_complete`:**
  Patched all 12 assertion checks (`0xb4fbb4`, `0xb4fd50`, `0xb517a8`, `0xb5189c`, `0xb51994`, `0xb51a78`, `0xb51b70`, `0xb51c68`, `0xb51d60`, `0xb51e58`, `0xb51f50`, `0xb52048`) to jump directly to clean stack teardown and return (`b 0xb52104` / `b 0xb52138`) whenever a filter packet is malformed or rejected.
- **Suppressed `vlog(FATAL)` Aborter (`0xd0d90c`):**
  Changed `b.ne 0xd0da74` to unconditional branch `b 0xd0da74`, ensuring that internal GD stack assertions log the diagnostic error to logcat but never terminate the process via `__android_log_call_aborter`.
- **Suppressed `LE_ENERGY_INFO`:**
  Ensured `BTM_BleGetEnergyInfo` never sends opcode `0xfd59` to controller.

### 2. Multi-Namespace APEX Bind Mounting (`service.sh`)
`service.sh` automatically injects the patched binary into both the **root init namespace** and **Zygote's mount namespace** using `nsenter`:
```bash
for ZPID in $(pidof zygote64 zygote); do
    nsenter -t "$ZPID" -m -- mount --bind "$MODDIR/libbluetooth_jni.so" /apex/com.android.bt/lib64/libbluetooth_jni.so
    nsenter -t "$ZPID" -m -- mount --bind "$MODDIR/libbluetooth_jni.so" /apex/com.android.bt@361099999/lib64/libbluetooth_jni.so
done
```
This guarantees the patched binary is loaded across reboots, app restarts, and Zygote re-forks.

### 3. Extended Timeouts & Sniff Interop Policy
- Extended HCI timeouts to 60,000ms:
  ```properties
  bluetooth.hci.timeout_milliseconds = 60000
  bluetooth.hci.restart_timeout_milliseconds = 60000
  ro.hw_timeout_multiplier = 3
  persist.bluetooth.sniff_offload.enabled = false
  ```
- Configured dynamic interop database (`/data/misc/bluedroid/interop_database_dynamic.conf` and `interop_database.conf`):
  ```ini
  [INTEROP_DISABLE_SNIFF]
  74:f6:7a = Address_Based     # Galaxy Watch6 Classic
  cc:f9:f0 = Address_Based     # Galaxy Buds2 Pro
  d0:39:fa = Address_Based     # Galaxy Buds2 Pro
  Galaxy Watch = Name_Based
  Galaxy Buds = Name_Based
  ```

### 4. Hardware Power Stabilization & LPM 0
- Set PCIe power controls to `on` across `1c00000.qcom,pcie`, `1c10000.qcom,pcie`, and `soc:bcmdhd_wlan`.
- Set `/proc/bluetooth/sleep/lpm` to `0`, completely stopping UART clock gating and byte framing corruption.
- Disabled broken Qualcomm Split-A2DP offload, forcing stable software encoding (supporting SBC, AAC, SSC Hi-Fi, LDAC).

---

## 📦 Installation Instructions

### Method 1: KernelSU / Magisk App (Recommended)
1. Download `Samsung-S20-Ultra-Bluetooth-Fix-v3.4.zip` from the [Releases](https://github.com/iamitgandhi/s20-ultra-5G_SM-G988N_Bluetooth-Disconnection-Fix/releases) tab.
2. Open **KernelSU** or **Magisk**.
3. Tap **Modules** -> **Install from storage**.
4. Select `Samsung-S20-Ultra-Bluetooth-Fix-v3.4.zip`.
5. Reboot your device when prompt appears.

### Method 2: Manual Installation via ADB
```bash
# Push zip to device
adb push Samsung-S20-Ultra-Bluetooth-Fix-v3.4.zip /data/local/tmp/

# Install using KernelSU / Magisk CLI
adb shell "su -M -c '/data/adb/ksud module install /data/local/tmp/Samsung-S20-Ultra-Bluetooth-Fix-v3.4.zip'"

# Reboot
adb reboot
```

---

## 🔍 Verification Commands

To verify that the fix is actively running on your device:

```bash
# 1. Check Bluetooth crash count and uptime (should show 0 crashes)
adb shell "dumpsys bluetooth_manager | grep -iE '(crashed|time since enabled)'"

# 2. Verify that the patched library is loaded in memory
BT_PID=$(adb shell "pidof com.android.bluetooth")
adb shell "su -M -c 'grep libbluetooth_jni.so /proc/$BT_PID/maps'"

# 3. Verify watch is actively connected over encrypted BR/EDR
adb shell "dumpsys bluetooth_manager | grep -C 2 'ACL BR/EDR:Y'"

# 4. Check PCIe power controls are locked to ON
adb shell "su -M -c 'cat /sys/devices/platform/soc/1c00000.qcom,pcie/power/control'"
```

---

## 🛠️ Building from Source

To package the flashable module ZIP yourself:
```bash
git clone https://github.com/iamitgandhi/s20-ultra-5G_SM-G988N_Bluetooth-Disconnection-Fix.git
cd s20-ultra-5G_SM-G988N_Bluetooth-Disconnection-Fix
chmod +x build_zip.sh
./build_zip.sh
```

---

## 🤝 Credits & Acknowledgments
- **Author:** Amit Kumar Gandhi ([@iamitgandhi](https://github.com/iamitgandhi))
- **Co-developed with:** Antigravity (Advanced Agentic AI Pair Programmer)
- **Target ROM:** UN1CA Team & ArtisanROM

---

## 📄 License
This project is licensed under the [MIT License](LICENSE).
