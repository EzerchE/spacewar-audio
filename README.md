# Spacewar Audio Policy

Version 1.3.0 is a limited policy-only maintenance release for the Nothing Phone (1)
(`Spacewar` / `A063`) running the supported crDroid 12.12 / Android 16 baseline
(2026-09-25). It is not a general audio fix or a promise of support for future ROMs.

## Purpose

The supported software-A2DP policy references an input-policy file absent from
that ROM. This module removes that single include and retains the existing
software-A2DP property configuration. The remaining ROM policy is unchanged.

Bluetooth calls, music playback, speaker handoff and volume control have been
validated on this baseline. Other ROM builds and long-term reliability have not
been established. Install only when this specific workaround is needed.

## Compatibility

Installation requires Spacewar/A063, Android 16/API 36, the exact original policy
SHA-256 `c17b85f06f23432ec412dbaed6211bfc57476276fe8c15f453f3350f26b6e537`
(or the exact patched policy
`ad2cb00ca2db53716f2ba301702c9148dc95a42bfb9196400b47220cbd47551c`), and
`/vendor/etc/a2dp_in_audio_policy_configuration.xml` to remain absent.

The same compatibility checks run at boot. An incompatible policy is not mounted.
This guard controls the policy overlay; the module's static Bluetooth properties
remain configured while the module is enabled.
After a ROM update, disable the module and reboot unless the new build has been
explicitly verified as supported.

## Install and remove

1. Download `spacewar-audio-v1.3.0.zip` and its `.sha256` file from the release.
2. Verify the ZIP checksum, install through KernelSU, and reboot.
3. If audio behavior worsens, disable or uninstall the module in KernelSU and reboot.

Disabling or uninstalling followed by a reboot restores the ROM policy and stops
applying this module's properties. No manual cache clearing is required.

Dolby and ViPER4Android apps, settings and presets are preserved. Version 1.3.0
contains no mixer override, audio guardian, RT tuning, telemetry or log collector.

## Changes in 1.3.0

- Retains software A2DP and the one-line input-policy correction.
- Removes guardian scheduling, call/media listeners and mixer overrides.
- Adds exact-baseline installation and boot compatibility checks.

Historical releases are legacy, remain available in the release history, and are
not recommendations for newer firmware. This repository is archived outside this
limited maintenance publication; broad future compatibility updates are not promised.

## Build

Run `python build.py`. The deterministic ZIP and SHA-256 file are written to
`dist/`. Run `python -m unittest discover -s tests -v` with Git Bash available to
validate shell syntax, compatibility guards, XML and package contents.
