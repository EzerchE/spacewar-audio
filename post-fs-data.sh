#!/system/bin/sh
# spacewar-audio: ROM'un a2dp_offload_disabled ses politikasi, cihazda olmayan
# a2dp_in_audio_policy_configuration.xml dosyasini include ediyor; bu nedenle
# ses egrileri cokup ses acma-kisma bozuluyor. Bu kopya mevcut 2026-08-11 ROM
# politikasini korur ve yalnizca gecersiz include satirini kaldirir. ROM'un
# deep_buffer FAST bayragi korunur.
MODDIR=${0%/*}
policy_src="$MODDIR/configs/audio_policy_configuration_a2dp_offload_disabled.xml"
policy_dst="/vendor/etc/audio_policy_configuration_a2dp_offload_disabled.xml"
if [ -f "$policy_src" ] && [ -f "$policy_dst" ]; then
    chcon u:object_r:vendor_configs_file:s0 "$policy_src" 2>/dev/null
    chmod 644 "$policy_src"
    mount --bind "$policy_src" "$policy_dst"
fi

# Rebased from the installed ROM mixer. Media PCM routes must not claim the
# same SLIMBUS_7 backend while the vendor HFP/SCO profile is being prepared.
# Native voice-call SCO RX/TX routes remain unchanged.
mixer_src="$MODDIR/configs/audio/sku_yupik/mixer_paths_yupikqrd.xml"
mixer_dst="/vendor/etc/audio/sku_yupik/mixer_paths_yupikqrd.xml"
if [ -f "$mixer_src" ] && [ -f "$mixer_dst" ]; then
    chcon u:object_r:vendor_configs_file:s0 "$mixer_src" 2>/dev/null
    chmod 644 "$mixer_src"
    mount --bind "$mixer_src" "$mixer_dst"
fi
