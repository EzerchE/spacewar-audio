#!/system/bin/sh
# spacewar-audio: ROM'un a2dp_offload_disabled ses politikasi, cihazda hic
# olmayan a2dp_in_audio_policy_configuration.xml dosyasini include ediyor;
# bu yuzden TUM ses egrileri cokup ses acma-kisma bozuluyor. Buradaki yamali
# kopya sadece o include satirini cikarir - baska hicbir degisiklik yok.
MODDIR=${0%/*}
src="$MODDIR/configs/audio_policy_configuration_a2dp_offload_disabled.xml"
dst="/vendor/etc/audio_policy_configuration_a2dp_offload_disabled.xml"
if [ -f "$src" ] && [ -f "$dst" ]; then
    chcon u:object_r:vendor_configs_file:s0 "$src" 2>/dev/null
    chmod 644 "$src"
    mount --bind "$src" "$dst"
fi
