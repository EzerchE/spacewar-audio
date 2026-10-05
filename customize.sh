#!/system/bin/sh
. "$MODPATH/compatibility.sh" || abort "Compatibility check unavailable."
compatible_policy "$MODPATH/configs/audio_policy_configuration_a2dp_offload_disabled.xml" ||
    abort "Unsupported baseline: Spacewar/A063 Android 16 with the exact supported audio policy is required."
ui_print "Spacewar Audio Policy 1.3.0: supported policy baseline confirmed."
ui_print "Reboot after installation."
