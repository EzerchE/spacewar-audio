#!/system/bin/sh

MODDIR=${0%/*}
CONFIG_FILE="$MODDIR/config.conf"
DEFAULTS_FILE="$MODDIR/defaults.conf"
PID_FILE="$MODDIR/guardian.pid"
EVENT_PID_FILE="$MODDIR/event-listener.pid"
FIFO_FILE="$MODDIR/events.fifo"
LOG_FILE="$MODDIR/guardian.log"
STATE_FILE="$MODDIR/stream.state"
GENERATION_FILE="$MODDIR/event.generation"
CODEC_FILE="$MODDIR/codec.state"
UNDERFLOW_FILE="$MODDIR/underflow.count"
LAST_MEDIA_APPLY_FILE="$MODDIR/last-media-apply"
TEST_FLOOR_FILE="$MODDIR/test-floor.state"
MODE=${1:-status}

RT_UCLAMP_MIN=20.00
IDLE_GRACE_SECONDS=30
START_BURST_DELAYS="1 3 10"
MEDIA_APPLY_DEBOUNCE_SECONDS=2
MEDIA_REAPPLY_DELAY_SECONDS=1
EVENT_RESTART_DELAY_SECONDS=5
MAX_LOG_SIZE_KB=256
LOG_THREAD_MOVES=0
UNDERFLOW_PERSIST_EVERY=8
CORE_AUDIO_PROCESSES="audioserver"
AUDIO_HAL_PROCESSES="android.hardware.audio.service android.hardware.audio.service-aidl android.hardware.audio@7.1-service android.hardware.audio@7.0-service android.hardware.audio@6.0-service"
BLUETOOTH_PROCESSES="com.android.bluetooth"
MEDIA_PACKAGES="com.spotify.music"
A2DP_OFFLOAD_DISABLED=true
DEFAULT_RT_UCLAMP_MIN=0.00
DEFAULT_RT_LATENCY_SENSITIVE=0

[ -r "$CONFIG_FILE" ] && . "$CONFIG_FILE"
[ -r "$DEFAULTS_FILE" ] && . "$DEFAULTS_FILE"

case "$UNDERFLOW_PERSIST_EVERY" in
  ''|*[!0-9]*|0) UNDERFLOW_PERSIST_EVERY=8 ;;
esac

rotate_log_if_needed() {
  [ -f "$LOG_FILE" ] || return
  LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null)
  [ -n "$LOG_SIZE" ] || return
  [ "$LOG_SIZE" -lt $((MAX_LOG_SIZE_KB * 1024)) ] && return
  mv -f "$LOG_FILE.1" "$LOG_FILE.2" 2>/dev/null
  mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null
}

log_message() {
  rotate_log_if_needed
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

is_running() {
  [ -r "$PID_FILE" ] || return 1
  GUARDIAN_PID=$(cat "$PID_FILE" 2>/dev/null)
  case "$GUARDIAN_PID" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$GUARDIAN_PID" 2>/dev/null || return 1
  [ -r "/proc/$GUARDIAN_PID/cmdline" ] || return 1
  CMDLINE=$(tr '\000' ' ' < "/proc/$GUARDIAN_PID/cmdline" 2>/dev/null)
  case "$CMDLINE" in
    *"$MODDIR/guardian.sh run"*) return 0 ;;
    *) return 1 ;;
  esac
}

next_generation() {
  GENERATION=$(cat "$GENERATION_FILE" 2>/dev/null)
  case "$GENERATION" in ''|*[!0-9]*) GENERATION=0 ;; esac
  GENERATION=$((GENERATION + 1))
  printf '%s\n' "$GENERATION" > "$GENERATION_FILE"
}

effective_rt_floor() {
  TEST_FLOOR=$(cat "$TEST_FLOOR_FILE" 2>/dev/null)
  case "$TEST_FLOOR" in
    10.00|20.00|30.00) printf '%s\n' "$TEST_FLOOR" ;;
    *) printf '%s\n' "$RT_UCLAMP_MIN" ;;
  esac
}

write_rt_group_properties() {
  TARGET_MIN=$1
  TARGET_LATENCY=$2
  [ -w /dev/cpuctl/rt/cpu.uclamp.min ] || return 1
  CURRENT_MIN=$(cat /dev/cpuctl/rt/cpu.uclamp.min 2>/dev/null)
  if [ "$CURRENT_MIN" != "$TARGET_MIN" ]; then
    printf '%s\n' "$TARGET_MIN" > /dev/cpuctl/rt/cpu.uclamp.min 2>/dev/null
    log_message "Set rt cpu.uclamp.min=$TARGET_MIN."
  fi
  if [ -w /dev/cpuctl/rt/cpu.uclamp.latency_sensitive ]; then
    CURRENT_LATENCY=$(cat /dev/cpuctl/rt/cpu.uclamp.latency_sensitive 2>/dev/null)
    if [ "$CURRENT_LATENCY" != "$TARGET_LATENCY" ]; then
      printf '%s\n' "$TARGET_LATENCY" > /dev/cpuctl/rt/cpu.uclamp.latency_sensitive 2>/dev/null
      log_message "Set rt latency_sensitive=$TARGET_LATENCY."
    fi
  fi
}

activate_rt_group() { write_rt_group_properties "$(effective_rt_floor)" 1; }
restore_idle_rt_group() { write_rt_group_properties "$DEFAULT_RT_UCLAMP_MIN" "$DEFAULT_RT_LATENCY_SENSITIVE"; }

thread_is_in_rt_group() {
  awk -F: '$2 ~ /(^|,)cpu(,|$)/ && $3 == "/rt" { found=1 } END { exit !found }' "$1/cgroup" 2>/dev/null
}

move_thread_to_rt_group() {
  PROCESS_NAME=$1
  THREAD_DIR=$2
  THREAD_ID=${THREAD_DIR##*/}
  thread_is_in_rt_group "$THREAD_DIR" && return
  if printf '%s\n' "$THREAD_ID" > /dev/cpuctl/rt/tasks 2>/dev/null; then
    THREAD_NAME=$(cat "$THREAD_DIR/comm" 2>/dev/null)
    PROTECTED_THREAD_COUNT=$((PROTECTED_THREAD_COUNT + 1))
    if [ "$LOG_THREAD_MOVES" = "1" ]; then
      log_message "Protected $PROCESS_NAME tid=$THREAD_ID name=$THREAD_NAME."
    fi
  fi
}

protect_process() {
  PROCESS_NAME=$1
  for PROCESS_ID in $(pidof "$PROCESS_NAME" 2>/dev/null); do
    for THREAD_DIR in /proc/$PROCESS_ID/task/*; do
      [ -d "$THREAD_DIR" ] || continue
      move_thread_to_rt_group "$PROCESS_NAME" "$THREAD_DIR"
    done
  done
}

is_media_audio_thread() {
  case "$1" in
    AAudio*|Audio*|AndroidAudio*|CCodecWatchdog|Codec2*|CodecLooper|ExoPlayer:Backg*|ExoPlayer:Playb*|MediaCodec*|Media\ Mixer\ Ren*|NDK\ MediaCodec_*|NuPlayer*|Oboe*) return 0 ;;
    *) return 1 ;;
  esac
}

protect_media_audio_threads() {
  PROCESS_NAME=$1
  for PROCESS_ID in $(pidof "$PROCESS_NAME" 2>/dev/null); do
    for THREAD_DIR in /proc/$PROCESS_ID/task/*; do
      [ -d "$THREAD_DIR" ] || continue
      THREAD_NAME=$(cat "$THREAD_DIR/comm" 2>/dev/null)
      is_media_audio_thread "$THREAD_NAME" || continue
      move_thread_to_rt_group "$PROCESS_NAME" "$THREAD_DIR"
    done
  done
}

apply_core_profile() {
  for PROCESS_NAME in $CORE_AUDIO_PROCESSES $AUDIO_HAL_PROCESSES $BLUETOOTH_PROCESSES; do protect_process "$PROCESS_NAME"; done
}

apply_media_profile() {
  for MEDIA_PACKAGE in $MEDIA_PACKAGES; do protect_media_audio_threads "$MEDIA_PACKAGE"; done
}

apply_active_profile() { activate_rt_group; apply_core_profile; apply_media_profile; }

apply_current_profile() {
  ensure_a2dp_offload_disabled
  case "$(cat "$STATE_FILE" 2>/dev/null)" in
    active|grace) apply_active_profile ;;
    *) restore_idle_rt_group ;;
  esac
}

ensure_a2dp_offload_disabled() {
  [ "$A2DP_OFFLOAD_DISABLED" = true ] || return 0
  [ "$(getprop persist.bluetooth.a2dp_offload.disabled 2>/dev/null)" = true ] && return 0
  RESETPROP_BIN=$(command -v resetprop 2>/dev/null)
  [ -n "$RESETPROP_BIN" ] || return 0
  "$RESETPROP_BIN" persist.bluetooth.a2dp_offload.disabled true 2>/dev/null
  log_message "Ensured canonical A2DP hardware offload-disabled property."
}

apply_media_profile_debounced() {
  [ "$(cat "$STATE_FILE" 2>/dev/null)" = active ] || return
  NOW=$(date +%s)
  LAST_APPLY=$(cat "$LAST_MEDIA_APPLY_FILE" 2>/dev/null)
  case "$LAST_APPLY" in ''|*[!0-9]*) LAST_APPLY=0 ;; esac
  [ $((NOW - LAST_APPLY)) -lt "$MEDIA_APPLY_DEBOUNCE_SECONDS" ] && return
  printf '%s\n' "$NOW" > "$LAST_MEDIA_APPLY_FILE"
  apply_media_profile
}

schedule_media_reapply() {
  [ "$(cat "$STATE_FILE" 2>/dev/null)" = active ] || return
  (
    sleep "$MEDIA_REAPPLY_DELAY_SECONDS"
    [ "$(cat "$STATE_FILE" 2>/dev/null)" = active ] || exit 0
    apply_media_profile
  ) &
}

schedule_start_burst() {
  BURST_GENERATION=$1
  (
    for DELAY_SECONDS in $START_BURST_DELAYS; do
      sleep "$DELAY_SECONDS"
      [ "$(cat "$GENERATION_FILE" 2>/dev/null)" = "$BURST_GENERATION" ] || exit 0
      [ "$(cat "$STATE_FILE" 2>/dev/null)" = active ] || exit 0
      apply_active_profile
    done
  ) &
}

set_stream_active() {
  PREVIOUS_STATE=$(cat "$STATE_FILE" 2>/dev/null)
  if [ "$PREVIOUS_STATE" = active ]; then
    apply_media_profile_debounced
    return
  fi
  next_generation
  printf '%s\n' active > "$STATE_FILE"
  # A2DP can resume while Telecom is still tearing down HFP/SCO. In that
  # narrow grace->active window, re-moving audioserver/Bluetooth/HAL threads
  # can race the vendor SCO teardown. Keep the RT floor and media protection,
  # but leave core audio thread placement unchanged until the next clean start.
  if [ "$PREVIOUS_STATE" = grace ]; then
    activate_rt_group
    apply_media_profile
    log_message "A2DP resumed from grace; skipped core audio/Bluetooth re-placement."
  else
    apply_active_profile
    schedule_start_burst "$GENERATION"
  fi
  [ "$PREVIOUS_STATE" = active ] || log_message "A2DP stream active; event-driven protection enabled."
}

schedule_stream_idle() {
  [ "$(cat "$STATE_FILE" 2>/dev/null)" = active ] || return
  persist_underflow_count
  next_generation
  IDLE_GENERATION=$GENERATION
  printf '%s\n' grace > "$STATE_FILE"
  log_message "A2DP stream stopped; idle restore scheduled in ${IDLE_GRACE_SECONDS}s."
  (
    sleep "$IDLE_GRACE_SECONDS"
    [ "$(cat "$GENERATION_FILE" 2>/dev/null)" = "$IDLE_GENERATION" ] || exit 0
    [ "$(cat "$STATE_FILE" 2>/dev/null)" = grace ] || exit 0
    printf '%s\n' idle > "$STATE_FILE"
    restore_idle_rt_group
    log_message "A2DP idle; restored captured RT defaults."
  ) &
}

record_codec() {
  DETECTED_CODEC=$(printf '%s\n' "$1" | sed -n 's/.*codec: \([^, ]*\).*/\1/p')
  [ -n "$DETECTED_CODEC" ] || return
  PREVIOUS_CODEC=$(cat "$CODEC_FILE" 2>/dev/null)
  printf '%s\n' "$DETECTED_CODEC" > "$CODEC_FILE"
  [ "$PREVIOUS_CODEC" = "$DETECTED_CODEC" ] || log_message "Observed Bluetooth codec=$DETECTED_CODEC; no codec setting changed."
}

record_underflow() {
  UNDERFLOW_COUNT=$((UNDERFLOW_COUNT + 1))
  if [ $((UNDERFLOW_COUNT % UNDERFLOW_PERSIST_EVERY)) -eq 0 ]; then
    printf '%s\n' "$UNDERFLOW_COUNT" > "$UNDERFLOW_FILE"
  fi
}

persist_underflow_count() {
  printf '%s\n' "$UNDERFLOW_COUNT" > "$UNDERFLOW_FILE"
}

handle_event() {
  EVENT_LINE=$1
  case "$EVENT_LINE" in
    *"bta2dp_audio_config_callback"*"codec: "*) record_codec "$EVENT_LINE" ;;
  esac
  case "$EVENT_LINE" in
    *"BTAV_AUDIO_STATE_STARTED"*|*"Connected: started playing:"*) set_stream_active ;;
    *"BTAV_AUDIO_STATE_STOPPED"*|*"Connected: stopped playing:"*|*"ON A2DP SUSPENDED"*) schedule_stream_idle ;;
    *"A2DP_SOFTWARE_ENCODING_DATAPATH"*"SetUp:"*|*"A2DP_SOFTWARE_ENCODING_DATAPATH"*"Start:"*) apply_core_profile ;;
    *"UNDERFLOW:"*|*"underflow "*) record_underflow ;;
  esac
}

detect_initial_stream_state() {
  INITIAL_CODEC=$(dumpsys bluetooth_manager 2>/dev/null | sed -n 's/^[[:space:]]*Current Codec: //p' | head -n 1)
  if [ -n "$INITIAL_CODEC" ]; then
    PREVIOUS_CODEC=$(cat "$CODEC_FILE" 2>/dev/null)
    printf '%s\n' "$INITIAL_CODEC" > "$CODEC_FILE"
    [ "$PREVIOUS_CODEC" = "$INITIAL_CODEC" ] || log_message "Observed Bluetooth codec=$INITIAL_CODEC; no codec setting changed."
  fi
  if dumpsys bluetooth_manager 2>/dev/null | grep -q 'mIsPlaying: true'; then
    set_stream_active
  else
    printf '%s\n' idle > "$STATE_FILE"
    restore_idle_rt_group
  fi
}

cleanup_listener() {
  EVENT_PID=$(cat "$EVENT_PID_FILE" 2>/dev/null)
  case "$EVENT_PID" in ''|*[!0-9]*) ;; *) kill "$EVENT_PID" 2>/dev/null ;; esac
  rm -f "$EVENT_PID_FILE" "$FIFO_FILE"
}

run_event_listener() {
  rm -f "$FIFO_FILE"
  mkfifo "$FIFO_FILE" || return 1
  # Keep the resident listener deliberately narrow. Codec, activity and power
  # tags are very noisy on this ROM and caused measurable shell/fork pressure
  # during UI transitions. Bluetooth stream events plus the finite start burst
  # are sufficient to place newly-created media/audio threads.
  logcat -b main,system -T 1 -v brief 'bluetooth-a2dp:I' 'A2dpStateMachine:I' 'BTAudioHalDeviceProxyAIDL:I' 'BTAudioSessionAidl:I' '*:S' > "$FIFO_FILE" 2>/dev/null &
  printf '%s\n' "$!" > "$EVENT_PID_FILE"
  while IFS= read -r EVENT_LINE; do handle_event "$EVENT_LINE"; done < "$FIFO_FILE"
  cleanup_listener
  return 1
}

run_guardian() {
  trap 'persist_underflow_count; cleanup_listener; exit 0' INT TERM EXIT
  UNDERFLOW_COUNT=$(cat "$UNDERFLOW_FILE" 2>/dev/null)
  case "$UNDERFLOW_COUNT" in
    ''|*[!0-9]*)
      UNDERFLOW_COUNT=0
      printf '%s\n' 0 > "$UNDERFLOW_FILE"
      ;;
  esac
  PROTECTED_THREAD_COUNT=0
  printf '%s\n' unknown > "$STATE_FILE"
  ensure_a2dp_offload_disabled
  detect_initial_stream_state
  log_message "Guardian started in event-driven mode."
  while true; do
    run_event_listener
    log_message "Event listener exited; restarting in ${EVENT_RESTART_DELAY_SECONDS}s."
    sleep "$EVENT_RESTART_DELAY_SECONDS"
  done
}

start_guardian() {
  if [ ! -w /dev/cpuctl/rt/tasks ] || [ ! -w /dev/cpuctl/rt/cpu.uclamp.min ]; then echo "Required RT cpuctl interfaces are unavailable."; return 1; fi
  if is_running; then echo "Guardian is already running with pid=$GUARDIAN_PID."; return 0; fi
  rm -f "$PID_FILE"
  nohup /system/bin/sh "$0" run >/dev/null 2>&1 &
  printf '%s\n' "$!" > "$PID_FILE"
  sleep 1
  echo "Guardian started with pid=$(cat "$PID_FILE" 2>/dev/null)."
}

stop_guardian() {
  if is_running; then kill "$GUARDIAN_PID" 2>/dev/null; sleep 1; fi
  cleanup_listener
  rm -f "$PID_FILE"
  restore_idle_rt_group
  log_message "Guardian stopped; captured RT defaults restored."
  echo "Guardian stopped."
}

set_test_floor() {
  case "$1" in
    10|10.00) TEST_FLOOR=10.00 ;; 20|20.00) TEST_FLOOR=20.00 ;; 30|30.00) TEST_FLOOR=30.00 ;;
    *) echo "Test floor must be 10, 20, or 30."; return 1 ;;
  esac
  printf '%s\n' "$TEST_FLOOR" > "$TEST_FLOOR_FILE"
  [ "$(cat "$STATE_FILE" 2>/dev/null)" = active ] && activate_rt_group
  log_message "Opt-in test floor selected: $TEST_FLOOR."
  echo "Test floor selected: $TEST_FLOOR"
}

clear_test_floor() {
  rm -f "$TEST_FLOOR_FILE"
  [ "$(cat "$STATE_FILE" 2>/dev/null)" = active ] && activate_rt_group
  log_message "Opt-in test floor cleared."
  echo "Test floor cleared."
}

show_status() {
  if is_running; then echo "Guardian is running with pid=$GUARDIAN_PID."; else echo "Guardian is not running."; fi
  echo "mode=event-driven"
  echo "stream_state=$(cat "$STATE_FILE" 2>/dev/null)"
  echo "codec=$(cat "$CODEC_FILE" 2>/dev/null)"
  echo "underflow_events=$(cat "$UNDERFLOW_FILE" 2>/dev/null)"
  echo "thread_move_logging=$LOG_THREAD_MOVES"
  echo "configured_rt_min=$RT_UCLAMP_MIN"
  echo "effective_rt_min=$(effective_rt_floor)"
  echo "rt_min=$(cat /dev/cpuctl/rt/cpu.uclamp.min 2>/dev/null)"
  echo "rt_latency=$(cat /dev/cpuctl/rt/cpu.uclamp.latency_sensitive 2>/dev/null)"
  echo "idle_rt_min=$DEFAULT_RT_UCLAMP_MIN"
  echo "idle_rt_latency=$DEFAULT_RT_LATENCY_SENSITIVE"
  echo "media_packages=$MEDIA_PACKAGES"
  echo "a2dp_offload_disabled=$(getprop persist.bluetooth.a2dp_offload.disabled 2>/dev/null)"
  tail -n 20 "$LOG_FILE" 2>/dev/null
}

case "$MODE" in
  start) start_guardian ;; run) run_guardian ;;
  apply) apply_current_profile; echo "Current audio profile applied." ;;
  stop) stop_guardian ;; test-floor) set_test_floor "$2" ;; clear-test) clear_test_floor ;; status) show_status ;;
  *) echo "Usage: $0 {start|apply|stop|test-floor 10|20|30|clear-test|status}"; exit 1 ;;
esac
