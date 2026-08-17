# Spacewar BTFM v3 build gate

This package builds the proposed Bluetooth SCO kernel fix against the kernel
revision recorded by the installed crDroid build manifest. It first builds an
**unmodified control module** and compares it with the module pulled from the
phone.

The patched module is published only when both checks pass:

1. exact kernel `vermagic` match;
2. exact imported-symbol CRC match (`CONFIG_MODVERSIONS`).

The workflow also asserts the installed device's Android clang build
(`clang-r563880c`, build 14054515), restores `/proc/config.gz`, and forces the
observed rollback kernel release string. A green compiler exit alone is not
treated as proof of ABI compatibility.

## Inputs

- `kernel-ci/input/device-config.gz`: pulled from `/proc/config.gz`.
- `kernel-ci/input/bt_fm_slim-stock.ko`: untouched module from the installed ROM.
- `kernel-ci/input/0001-bluetooth-btfm-slim-ready-retry-v3.patch`: source patch.

## Safety boundary

Do not load any output from the diagnostics artifact. Only an artifact named
`spacewar-btfm-v3-abi-verified` containing `VERIFIED.txt` has passed the ABI
gate. Even that module must first be tested through a recoverable boot image or
module replacement plan; the live driver must not be unbound/rebound because
that path already reproduced a double-free of IRQ 304/305.

This package does not flash, push, reboot, or modify a phone.
