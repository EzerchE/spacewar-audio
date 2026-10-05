#!/system/bin/sh
# Exact policy baseline; checking compatibility does not change the device.
ORIGINAL_POLICY_SHA256=c17b85f06f23432ec412dbaed6211bfc57476276fe8c15f453f3350f26b6e537
PATCHED_POLICY_SHA256=ad2cb00ca2db53716f2ba301702c9148dc95a42bfb9196400b47220cbd47551c
POLICY_TARGET=/vendor/etc/audio_policy_configuration_a2dp_offload_disabled.xml
MISSING_INPUT_POLICY=/vendor/etc/a2dp_in_audio_policy_configuration.xml

policy_sha256() { sha256sum "$1" 2>/dev/null | cut -d ' ' -f 1; }

compatible_policy() {
    case "$(getprop ro.product.device)" in Spacewar|spacewar) ;; *) return 1 ;; esac
    [ "$(getprop ro.product.model)" = A063 ] || return 1
    [ "$(getprop ro.build.version.release)" = 16 ] || return 1
    [ "$(getprop ro.build.version.sdk)" = 36 ] || return 1
    [ ! -e "$MISSING_INPUT_POLICY" ] && [ ! -L "$MISSING_INPUT_POLICY" ] || return 1
    [ -f "$1" ] && [ -f "$POLICY_TARGET" ] || return 1
    [ "$(policy_sha256 "$1")" = "$PATCHED_POLICY_SHA256" ] || return 1
    POLICY_TARGET_SHA256=$(policy_sha256 "$POLICY_TARGET")
    case "$POLICY_TARGET_SHA256" in
        "$ORIGINAL_POLICY_SHA256"|"$PATCHED_POLICY_SHA256") return 0 ;;
        *) return 1 ;;
    esac
}
