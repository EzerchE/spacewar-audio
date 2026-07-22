# Spacewar Audio Stability

KernelSU module for the Nothing Phone (1) (`Spacewar`) running crDroid 12 / Android 16.

## What it does

`spacewar-audio` addresses intermittent Bluetooth A2DP crackling, dropouts and post-call audio recovery by keeping the affected media path in software mode and applying a small event-driven scheduling assist while audio is active.

Version 1.2.2 adds a post-call resume safeguard: when A2DP returns while the HFP/SCO teardown is still settling, the module avoids re-placing core audio, Bluetooth and Audio HAL threads. This reduces the race that previously caused Bluetooth music or call audio to disappear after a call.

## Scope and safety

- V4A, Dolby, mixer files and call-routing configuration are not modified.
- No resident polling loop is used while the device is idle.
- The module is reversible through KernelSU.
- It was created and tested specifically on Spacewar. Testing on another device is appropriate only when its Bluetooth/audio stack and symptoms are genuinely similar; compatibility is not guaranteed.

This is an independent community workaround, not an official crDroid, Nothing, Qualcomm or Android fix. Use it at your own risk and keep a recovery path before testing.

## Install / rollback

Install `spacewar-audio-v1.2.2.zip` from KernelSU and reboot. Disable or uninstall it from KernelSU to roll back. The module does not replace the system audio stack and does not require removing V4A or Dolby.

## Changelog

### 1.2.2

- Added safer A2DP resume handling after HFP/SCO calls.
- Preserved the tested media protection without reapplying core audio thread placement during the post-call grace window.
- No changes to V4A, Dolby, mixer or notification behavior.

### 1.2.0

- Initial public event-driven A2DP stability release.
