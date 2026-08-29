# Spacewar Audio Stability

KernelSU module for the Nothing Phone (1) (`Spacewar`) running crDroid 12 / Android 16.

## What it does

`spacewar-audio` addresses intermittent Bluetooth A2DP crackling and dropouts by keeping the affected media path in software mode and applying an event-driven scheduling assist only while Bluetooth media is active.

Version 1.2.6 keeps the 1.2.5 media profile and the locally tested SCO recovery combination. Its mixer file is rebased from the installed ROM and prevents media PCM paths from claiming `SLIMBUS_7` during HFP/SCO setup; native voice-call routes are left intact. Call-aware scheduling is enabled only for the duration of a call.

## Scope and safety

- V4A and Dolby packages, settings and presets are not removed or rewritten.
- The module overlays the A2DP software policy and the current-ROM
  `mixer_paths_yupikqrd.xml`; 22 media-only SCO controls are disabled while
  native voice-call SCO RX/TX routes remain present. Disabling the module
  restores both ROM files.
- No resident polling loop is used while the device is idle.
- The module is reversible through KernelSU.
- It was created and tested specifically on Spacewar. Testing on another device is appropriate only when its Bluetooth/audio stack and symptoms are genuinely similar; compatibility is not guaranteed.

This is an independent community workaround, not an official crDroid, Nothing, Qualcomm or Android fix. Use it at your own risk and keep a recovery path before testing.

## Install / rollback

Install `spacewar-audio-v1.2.6.zip` from KernelSU and reboot. Disable or uninstall it from KernelSU to roll back. The module does not replace the system audio stack and does not require removing V4A or Dolby.

The Bluetooth HFP/SCO failure is timing-sensitive and originates below the app
layer. This release is a tested mitigation for the maintainer's Spacewar, not a
guarantee for every ROM/kernel build. If call audio is worse after installation,
disable the module and reboot before collecting logs.

## Changelog

### 1.2.6

- Rebased the previously successful Spacewar SCO mixer workaround onto the currently installed ROM mixer.
- Disabled only media playback/record controls that compete for `SLIMBUS_7`; retained native voice-call SCO RX/TX paths.
- Restored bounded call-aware RT protection from the last working local configuration.
- Kept the 1.2.5 deep-buffer media profile, volume-policy correction and V4A/Dolby compatibility.
- Passed repeated Bluetooth media, call, volume-control and disconnect tests,
  including first-call tests after controlled reboots on the target device.

### 1.2.5-local

- Removed the ineffective call-aware scheduling and Telecom/kernel log listener added in 1.2.4-local.
- Kept software A2DP, the invalid A2DP-input include correction and active-only 30 percent RT floor.
- Changed deep buffer from `FAST|DEEP_BUFFER` to `DEEP_BUFFER` only, matching the earlier stable media profile and favoring continuity over low latency.
- Kept narrowly filtered underrun recovery; idle still restores the ROM defaults.

### 1.2.4-local

- Rebased the one-line volume-policy correction onto the installed 2026-08-11 ROM policy, retaining `AUDIO_OUTPUT_FLAG_FAST|AUDIO_OUTPUT_FLAG_DEEP_BUFFER`.
- Raised the active-only RT utilization floor to the previously tested 30 percent profile; idle still restores the ROM default.
- Added narrowly filtered AudioFlinger underrun recovery without an idle polling loop.
- Added call-aware SCO transition protection and bounded call-start thread-placement bursts.
- Added persistent counting of kernel `btfm_slim` / `SLIMBUS_7` setup failures.

### 1.2.3

- Retries guardian startup when the RT control interfaces become available shortly after `boot_completed`.
- Confirms the guardian is running before ending the startup sequence.
- Leaves the event-driven audio behavior unchanged.

### 1.2.2

- Added safer A2DP resume handling after HFP/SCO calls.
- Preserved the tested media protection without reapplying core audio thread placement during the post-call grace window.
- No changes to V4A, Dolby, mixer or notification behavior.

### 1.2.0

- Initial public event-driven A2DP stability release.
