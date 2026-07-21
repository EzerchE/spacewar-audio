# Spacewar Audio Stability

KernelSU module created and tested for the Nothing Phone (1) (`Spacewar`) running crDroid 12 / Android 16.

It targets intermittent Bluetooth A2DP music crackling and dropouts by keeping the affected audio path in software mode and applying a small, event-driven scheduling assist only while media audio is active.

## Scope

- Bluetooth A2DP music stability
- No V4A, Dolby, mixer, notification, or call-routing files are modified
- No resident polling loop while idle
- Reversible through KernelSU

This is an independent community workaround, not an official crDroid, Nothing, Qualcomm, or Android fix. It was created specifically for Spacewar. Testing on another device is appropriate only when the Bluetooth/audio stack and symptoms are genuinely similar; compatibility is not guaranteed.

Install the ZIP from KernelSU and reboot. Disable or uninstall it from KernelSU to roll back. Use at your own risk and keep a recovery path before testing.
