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

# Some boots expose the RT control group a little later than boot_completed.
# Retry only during startup; idle operation remains event-driven and unchanged.
attempt=1
while [ "$attempt" -le 6 ]; do
  /system/bin/sh "$MODDIR/guardian.sh" start >> "$MODDIR/service.log" 2>&1
  sleep 2
  if /system/bin/sh "$MODDIR/guardian.sh" status 2>/dev/null | grep -q "Guardian is running"; then
    exit 0
  fi
  echo "Guardian startup retry $attempt/6; RT interfaces may not be ready yet." >> "$MODDIR/service.log"
  sleep 10
  attempt=$((attempt + 1))
done

echo "Guardian did not start after 6 startup attempts." >> "$MODDIR/service.log"
