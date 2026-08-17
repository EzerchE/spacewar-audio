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

## Current result (2026-08-17)

The control build completed with the expected kernel release and matching
`vermagic`, but it **failed the imported-symbol ABI gate**. The stock module
imports 41 versioned symbols while the reproducible public-source build imports
40, and many CRCs differ, including `module_layout`, `slim_driver_register`,
`slim_query_ch` and `slim_request_val_element`.

The installed kernel identifies itself as `dirty`; the public manifest commit
also lacks two KernelSU/SUSFS fixes present in the installed build. KernelSU was
disabled only in the isolated control build so unrelated source errors would
not conceal the BTFM comparison. The CRC gate still failed after the full
control kernel and modules built successfully.

Consequently, no patched module was published and no kernel object from this
branch is safe to load. Reproducing the maintainer's exact dirty source/build
tree (or integrating the patch into a complete ROM kernel build) is required.
See [Actions run 13](https://github.com/EzerchE/spacewar-audio/actions/runs/32026271561).

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
