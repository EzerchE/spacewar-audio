#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/compatibility.sh" || exit 1
POLICY_SOURCE="$MODDIR/configs/audio_policy_configuration_a2dp_offload_disabled.xml"
compatible_policy "$POLICY_SOURCE" || exit 0
[ "$POLICY_TARGET_SHA256" != "$PATCHED_POLICY_SHA256" ] || exit 0
chmod 0644 "$POLICY_SOURCE" || exit 1
chcon u:object_r:vendor_configs_file:s0 "$POLICY_SOURCE" 2>/dev/null || exit 1
mount --bind "$POLICY_SOURCE" "$POLICY_TARGET" 2>/dev/null || exit 1
