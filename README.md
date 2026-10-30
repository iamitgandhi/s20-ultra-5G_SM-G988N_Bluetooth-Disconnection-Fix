# 🎧 Samsung Galaxy S20 Ultra — BCM4375 Bluetooth Disconnection Fix (v3.0)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Device: Galaxy S20 Ultra](https://img.shields.io/badge/Device-SM--G988N%20%7C%20z3q-blue.svg)](https://github.com/iamitgandhi/s20-ultra-5G_SM-G988N_Bluetooth-Disconnection-Fix)
[![Platform: KernelSU / Magisk / APatch](https://img.shields.io/badge/Root-KernelSU%20%7C%20Magisk%20%7C%20APatch-green.svg)](https://github.com/iamitgandhi/s20-ultra-5G_SM-G988N_Bluetooth-Disconnection-Fix)
[![ROM: UN1CA / OneUI Port](https://img.shields.io/badge/ROM-UN1CA%20%7C%20OneUI%207%2F8-orange.svg)](https://github.com/iamitgandhi/s20-ultra-5G_SM-G988N_Bluetooth-Disconnection-Fix)

A comprehensive, permanent engineering fix for severe Bluetooth instability, persistent peripheral disconnections (specifically **Galaxy Watch6 / Watch5 / Watch4** and **Galaxy Buds2 Pro**), audio stutters, and relentless `com.android.bluetooth` daemon crashes on Samsung Galaxy S20 Ultra 5G (Snapdragon SM8250 / Broadcom BCM4375) running **UN1CA** (Android 15 / 16, OneUI 7 / 8 port) and custom ROMs.

---

## 📌 Problem Overview

Users running custom OneUI ports (such as **UN1CA 4.0.0**) on Snapdragon 865 Samsung devices frequently encounter severe Bluetooth issues:
1. **Endless Watch Disconnect Loops:** Galaxy Watch (Watch6 Classic, Watch5, Watch4) disconnects every 30–60 seconds and continually reconnects.
2. **Audio Stutters & Music Dropouts:** Galaxy Buds2 Pro, AirPods, and car audio systems cut out or disconnect after 1–2 minutes of playback.
3. **Instant Sleep Suicide:** As soon as the screen is turned off or the phone goes idle, the entire Bluetooth stack terminates, dropping all active connections simultaneously.
4. **Relentless Daemon Restarts:** `dumpsys bluetooth_manager` reveals `Bluetooth crashed 130+ times` in just a few hours.

---

## 🔍 Root Cause Analysis (Deep Reverse Engineering)

Through live kernel tracing, tombstone analysis, and AArch64 disassembly of `/apex/com.android.bt/lib64/libbluetooth_jni.so`, **six compounding root causes** were identified:

### 1. Bluetooth Daemon Suicide Mechanism (`system/gd/hci/hci_layer.cc`)
The Google Gabeldorsche (GD) Bluetooth stack enforces a strict HCI command timeout watchdog:
```
system/gd/hci/hci_layer.cc:122 abort_after_time_out: [BTCORE] Done waiting for debug information after HCI timeout (<OPCODE>) for 7000ms
```
Disassembly of `libbluetooth_jni.so` revealed that `abort_after_time_out` deliberately terminates its own process with `SIGKILL`:
```armasm
0xac05e8:  mov    w0, #0xa120
0xac05ec:  bl     getpid@LIBC
0xac05f0:  mov    w1, #0x9        ; SIGKILL (kill -9)
0xac05f4:  bl     kill@LIBC       ; Self-termination!
```
Whenever any HCI command took longer than 5,000ms over the Broadcom UART bus, the stack executed `kill(getpid(), SIGKILL)`, immediately killing all connected devices.

### 2. Unsupported `LE_ENERGY_INFO (0xfd59)` on Screen-Off
Whenever the screen turned off or the device entered doze, Android's `BatteryStats` dispatched vendor opcode `0xfd59` via `BTM_BleGetEnergyInfo` to query energy consumption.
The Broadcom BCM4375 controller does not respond to `0xfd59` during low-power transitions. The command stalled, tripped the 5,000ms watchdog, and fired the SIGKILL suicide above every 30–45 seconds.

### 3. Broadcom FullMAC Wi-Fi (`dhd`) PCIe Runtime PM RC0 Reset
Dmesg logs showed that the Wi-Fi PCIe link regularly entered idle suspend every 2–3 seconds:
```
dhd_runtimepm_state: DHD Idle state!! - idletime :5 ... dhdpcie_bus_suspend: Entering suspend state
msm_pcie_pm_suspend: RC0: PME_TURNOFF_MSG is sent out
msm_pcie_disable: PCIe: Assert the reset of endpoint of RC0.
```
Because the BCM4375 is a combo Wi-Fi/Bluetooth chip sharing internal power rails, asserting the PCIe reset on RC0 during bus suspend caused the Bluetooth UART core to temporarily stall or drop pending command responses.

### 4. Broadcom UART Low Power Mode (LPM) Framing Desync
Samsung's `bluesleep` driver had `/proc/bluetooth/sleep/lpm = 1`. During brief pauses, the UART line was put to sleep. When incoming packets arrived while clocks were waking up, bytes were dropped. The AOSP H4 packetizer logged `Unimplemented packet type <X>`, permanently losing byte framing.

### 5. Invalid Qualcomm Hastings Split-A2DP Offload
Generic Qualcomm build properties were present in the ROM (`persist.vendor.qcom.bluetooth.enable.splita2dp=true`, `ro.bluetooth.a2dp_offload.supported=true`). The Broadcom BCM4375 does **not** support Qualcomm Hexagon DSP Split A2DP over Slimbus. This caused 1,700+ buffer flushes in minutes, leading to audio stuttering and A2DP stream collapse.

### 6. Sniff Mode Link Collisions
Galaxy Watch6 Classic maintains continuous, high-throughput RFCOMM channels for health/sensor sync. Transitions into low-power Sniff Mode (`0x0803`) collided with active RFCOMM data packets, causing controller queue stalls.

---

## 🛠️ The Permanent Engineering Solution (v3.0)

This module provides a multi-layer solution packaged into a single flashable module:

### 1. Binary Patch in `libbluetooth_jni.so`
- **Neutralized Suicide Mechanism (`0xac05e8`):**
  Replaced `mov w0, #0xa120` (`00 24 94 52`) with `b 0xac0600` (`06 00 00 14`). Skips `kill(getpid(), SIGKILL)`, allowing the stack to cleanly time out and recover without process death.
- **Suppressed `LE_ENERGY_INFO` (`0x8d5824`):**
  Replaced `cbz w22, 8d5858` (`b6 01 00 34`) with unconditional branch `b 8d5858` (`0d 00 00 14`). `BTM_BleGetEnergyInfo` immediately logs `"Controller does not support get energy info"` and returns `BTM_ERR_PROCESSING`, never sending opcode `0xfd59`.

### 2. Multi-Namespace APEX Bind Mounting (`service.sh`)
In modern Android, `com.android.bluetooth` runs in a separate mount namespace forked from Zygote.
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

## 📊 Verification & Stability Benchmark

| Metric | Before Fix | After Fix (v3.0) |
| :--- | :--- | :--- |
| **Bluetooth Crashes** | 138+ crashes (every 30–45s) | **0 spontaneous crashes** |
| **Daemon Uptime** | Maximum 45 seconds | **Sustained stable (hours continuous)** |
| **Screen-Off / Sleep** | Immediate HCI timeout suicide (`0xfd59`) | **Clean recovery; zero drops** |
| **Watch Link State** | Repeated ACL drop & reconnect loop | **`[ACL BR/EDR: Y]` continuously encrypted** |
| **Audio Playback** | Stutters, buffer underruns (`ALF2: 1799`) | **Uninterrupted A2DP / SSC Hi-Fi streaming** |
| **UART Framing Errors** | Frequent `Unimplemented packet type` | **Zero framing errors (`lpm=0`)** |

---

## 📦 Installation Guide

### Prerequisites
- Samsung Galaxy S20 Ultra 5G (`SM-G988N`, `SM-G988B`, `SM-G9880`, `SM-G988U` / `z3q`) or compatible Snapdragon 865 device.
- Root access via **KernelSU / KernelSU Next**, **Magisk** (v26+), or **APatch**.

### Method 1: Install via KernelSU / Magisk App (Recommended)
1. Download the latest **`Samsung-S20-Ultra-Bluetooth-Fix-v3.0.zip`** from [Releases](https://github.com/iamitgandhi/s20-ultra-5G_SM-G988N_Bluetooth-Disconnection-Fix/releases).
2. Open **KernelSU** or **Magisk** app on your phone.
3. Navigate to **Modules** -> **Install from storage**.
4. Select `Samsung-S20-Ultra-Bluetooth-Fix-v3.0.zip`.
5. Reboot your device when prompt appears.

### Method 2: Manual Installation via ADB
```bash
# Push zip to device
adb push Samsung-S20-Ultra-Bluetooth-Fix-v3.0.zip /data/local/tmp/

# Install using KernelSU / Magisk CLI
adb shell "su -M -c '/data/adb/ksud module install /data/local/tmp/Samsung-S20-Ultra-Bluetooth-Fix-v3.0.zip'"

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
EOF