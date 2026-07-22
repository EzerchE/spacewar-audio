#!/system/bin/sh

MODDIR=${0%/*}

# Keep only the latest boot-start records. The event log has its own bounded
# rotation in guardian.sh.
[ -f "$MODDIR/service.log" ] && tail -20 "$MODDIR/service.log" > "$MODDIR/service.log.tmp" 2>/dev/null
[ -f "$MODDIR/service.log.tmp" ] && mv -f "$MODDIR/service.log.tmp" "$MODDIR/service.log"

while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 5
done

sleep 10
/system/bin/sh "$MODDIR/guardian.sh" start >> "$MODDIR/service.log" 2>&1
