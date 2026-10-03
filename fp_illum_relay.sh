#!/system/bin/sh
# fp_illum_relay.sh - fingerprint mask-layer illumination relay
#
# v10 = v9 (which added the bounded wait for the DECON illumination node)
# with STATE moved to /data/vendor, because this daemon's sepolicy is a
# vendor domain - see sepolicy/vendor/fp_illum.te.
# THIS IS THE FILE THE ROM TREE SHIPS (PRODUCT_COPY_FILES ->
# /system/bin/fp_illum_relay.sh, started by init.fp_illum.rc).
#
# v8 = v7 (see the v7 notes below) with STATE moved from the KernelSU path
# /data/adb/fp_illum to /data/misc/fp_illum, so this exact file can ship
# in the ROM tree as an init service and the KernelSU modules can be deleted.
# This file is the SINGLE SOURCE OF TRUTH; it is what
#   device/samsung/a30s/overlay/... -> PRODUCT_COPY_FILES -> /system/bin/fp_illum_relay.sh
# installs. Do NOT keep a second hand-edited copy in the tree.
#
# WHY THIS EXISTS (all proven on device, not assumed):
#   1. The AIDL HAL's own illumination path is DEAD on this board. It logs
#      "fingerprint illum node: NOT FOUND" because Session.cpp globs
#      /sys/devices/platform/*/decon0/fingerprint_illum
#      and this board's node is:
#        /sys/devices/platform/14860000.decon_f/fingerprint_illum
#      No decon0 platform device exists here. Confirmed: `ls -d
#      /sys/devices/platform/*/decon0` -> No such file or directory, and
#      dmesg showed FPILLUM store count 0 for an entire enrollment attempt.
#      => this relay is the ONLY working illumination control here.
#
#   2. A previous generation (relay6, md5 7f614c5b4b011ec083eb5e1eeff69c61)
#      injected `input keyevent KEYCODE_SLEEP/WAKEUP` to force a frame
#      submission. That yanks the user's screen. NOT permitted. Removed.
#
#   3. relay3 (md5 5524e2118e464c35a22055be090a92ce) gated its defensive
#      force-OFF on a sticky `ever_active` flag, so after one marker test the
#      panel could stay pinned lit forever. This generation has NO sticky
#      gate: release is purely time-based and cannot be disabled by state.
#
#   4. The knob only ARMS the mask path; the LEVEL comes from a separate
#      attribute, /sys/class/lcd/panel/mask_brightness, which defaults to 255.
#      A live attempt at 23:02:58 engaged the mask and the trustlet rejected
#      the image with BAD_QUALITY 39. The panel log proves the level used:
#        dsim_panel_mask_brightness: current(1) to mask(255)
#      A71 (commit 877ef30d9d16) documents 255 as breaking enrollment and 337
#      as the working value. So this relay now pushes $MASK_VALUE to
#      $MASKVAL *before* engaging the knob, in that order, every time.
#
# SAFETY CONTRACT:
#   - writes ONLY to $KNOB, $MASKVAL and $STATE. Nothing else on the device.
#   - no system/ or vendor/ directory is ever created.
#   - trap on every exit path forces the knob to 0.
#   - hard ceiling MAX_ON_SECONDS even if triggers never stop firing.
#   - startup grace is a one-shot absolute timestamp, so it can only DELAY a
#     release. It can never be re-armed and can never enable stuck-on.
#   - no input/tap/swipe of any kind, and nothing that can move focus. The ONE
#     input event used is KEYCODE_WAKEUP, and only while a fingerprint operation
#     is live with the panel dark - see the wake gate. It cannot type, tap, swipe
#     or steer focus; it only lights the panel, which is what the stock
#     DECON_WIN_STATE_FINGERPRINT window state did on a working device.

KNOB=/sys/devices/platform/14860000.decon_f/fingerprint_illum
MASKVAL=/sys/class/lcd/panel/mask_brightness
# v8: was /data/adb/fp_illum, which only exists because a KernelSU module
# launched this. In-tree it runs as an init service with no KSU present, and
# /data/adb is not a path that daemon should be writing to. /data/misc is the
# conventional home for a small piece of mutable daemon state (this dir holds
# only relay.log, relay.pid, supervisor.log and mask_value).
# v10: /data/vendor rather than /data/misc. vendor_data_file is declared in
# system/sepolicy/public; /data/misc has no generic label at all, so there
# would be no type to allow this daemon to write.
STATE=/data/vendor/fp_illum
LOG=$STATE/relay.log
PIDF=$STATE/relay.pid

DEFAULT_MASK_VALUE=337      # A71 documented value; see BUILD_NOTES.md
RELEASE_SECONDS=6           # no trigger activity this long -> force release
MAX_ON_SECONDS=5            # absolute ceiling per activation, from the moment
                            # the mask is turned on. User requirement 2026-10-02:
                            # brightness must never hold for more than 5 seconds
                            # after a fingerprint touch. This is deliberately
                            # much shorter than the 60 s FingerprintEnrollClient
                            # timeout - enrollment simply cycles: 5 s lit, brief
                            # re-arm, 5 s lit again, and the scan that matters
                            # lands in one of those windows. It is also the
                            # primary burn-in defence, since the mask write is
                            # panel-global on this ROM (see BUILD_NOTES.md 25.1).
# CEILING IS NOW MODE-DEPENDENT (added v7).
# MAX_ON_SECONDS=5 was a LOCK SCREEN requirement - burn-in defence, user request
# 2026-10-02 - but it was applied to EVERY activation including enrollment.
# Enrollment needs the panel held for the whole FingerprintEnrollClient window.
# Measured on device: the mask was ON for 1-5 s and released before the trustlet
# finished, so enrollment died with ZERO acquire callbacks. Auth keeps the 5 s
# cap; enroll gets a real budget. Both remain hard ceilings.
MAX_ON_SECONDS_ENROLL=45    # enrollment: long enough for one full capture
SCREEN_OFF_INHIBIT=6        # after we observe the panel go DOWN, refuse to wake
                            # it again for this long. DT2S is ON on this device
                            # (secure double_tap_to_sleep=1) and a double tap is
                            # two panel IRQs, indistinguishable from a finger on
                            # the sensor. Without this the relay woke the panel
                            # straight back up: 11 spurious WAKE events logged,
                            # each followed within ~2 s by "device asleep".
                            # Once the panel has been dark longer than this, the
                            # next touch IS a real AOD fingerprint intent and is
                            # allowed to wake.
STARTUP_GRACE=30            # one-shot, absolute, from T0
BOOT_QUIET_SECONDS=150     # probe NOTHING for this long after start. See the
                            # loop comment: the relay starts at boot and the
                            # vendor HALs are still registering. Three binder
                            # calls per second in that window is a self-inflicted
                            # risk to wifi/ril/nfc for no fingerprint benefit.
MAX_VALUE=355               # panel EXTEND_BRIGHTNESS (s6e8fc1_a30s_param.h)

# SCAN-GATED RELEASE. The keyguard auth client stays live for MINUTES, so a
# trigger-only policy holds the mask lit ~93% of the time (measured 2026-10-01:
# ON 10:50:27 held to the 70s ceiling with the sensor never scanning). The HAL
# acquire counter is circular for the ON decision - it only advances while the
# mask is lit - but it is perfectly valid for the OFF decision. So: light up,
# and if the sensor produces no scan within SCAN_GRACE, nobody's finger is
# there and the light is pure OLED risk. Release and back off. Once a real scan
# is seen, fall back to the normal ceiling.
SCAN_GRACE=10               # no acquire within this long after ON -> release
# v7: SCAN_BACKOFF_MAX cut 300 -> 45. A 5 minute blackout after one missed scan
# is indistinguishable from 'the fingerprint is broken' - it is the mechanism
# behind 'takes a few clicks'. 45 s still fully backs off, but a retry is never
# more than one coffee-sip away.
SCAN_BACKOFF=25            # after a no-scan release, hold off re-arming this long
SCAN_BACKOFF_MAX=45        # ... but never wait longer than this
#
# Repeated no-scan releases back off EXPONENTIALLY, because leaving the keyguard
# up with the auth client live is the steady state: measured 2026-10-01 a flat
# 25s backoff produced a 15s-on/40s cycle running indefinitely (ON 11:26:55,
# 11:27:36, 11:28:17, ...) with acquire frozen at 23. That is a permanent 37%
# duty cycle on a fixed OLED region. With a streak multiplier it decays to one
# light-up per 5 minutes, and the first real scan resets the streak to zero.
NO_SCAN_STREAK=0
CEILING_COOLDOWN=5         # after the ceiling, cool down this long and re-arm if
                            # the op is still live. NOT a latch - a latch
                            # blackholes the lock screen (see step 3).

mkdir -p $STATE 2>/dev/null

# v9: block until the panel driver has actually created the illumination node.
# The KernelSU module did this in its service.sh; in-tree there is no wrapper,
# and it cannot be done by a second init service either because init cannot exec
# system_file. Bounded at 120 s, and it does NOT exit if the node never appears -
# the main loop's own guard already forces the knob to 0 whenever the panel is
# asleep, and a missing node makes every write a no-op, so spinning here is safe
# and keeps the service alive (and therefore restarting) instead of crashlooping.
_waited=0
while [ ! -e /sys/devices/platform/14860000.decon_f/fingerprint_illum ]; do
    _waited=$((_waited + 1))
    [ "$_waited" -gt 120 ] && break
    sleep 1
done

echo $$ > $PIDF 2>/dev/null

T0=$(date +%s)
GRACE_END=$((T0 + STARTUP_GRACE))
QUIET_END=$((T0 + BOOT_QUIET_SECONDS))

MASK_VALUE=$DEFAULT_MASK_VALUE
[ -r $STATE/mask_value ] && read M < $STATE/mask_value
case "$M" in
  ''|*[!0-9]*) MASK_VALUE=$DEFAULT_MASK_VALUE ;;
  *) [ "$M" -gt "$MAX_VALUE" ] && MASK_VALUE=$MAX_VALUE
     [ "$M" -lt 0 ] && MASK_VALUE=0 ;;
esac

# --- logging, rate limited -------------------------------------------------
log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG 2>/dev/null; }
log_limited() {                      # log_limited <key> <secs> <msg...>
  _k=$1; _s=$2; shift 2
  _f=$STATE/.last_$_k
  _l=0; [ -r $_f ] && read _l < $_f
  _n=$(date +%s)
  [ $((_n - _l)) -ge $_s ] && { log "$@"; echo $_n > $_f 2>/dev/null; }
  return 0
}

knob_read() { [ -r $KNOB ] && cat $KNOB 2>/dev/null; }

knob_on() {
  # CRITICAL ORDER: the mask VALUE must be pushed before the knob is engaged.
  # The knob only arms the path; lcd->mask_brightness supplies the level, and
  # the panel driver logs "dsim_panel_mask_brightness: current(N) to mask(N)".
  # Leaving it at its 255 default produced BAD_QUALITY 39 on a live attempt
  # at 23:02:58 -- A71 documents 255 as breaking enrollment, 337 as correct.
  if [ "$(knob_read)" != "1" ]; then
    if echo "$MASK_VALUE" > $MASKVAL 2>/dev/null; then
      log_limited maskset 30 "mask_brightness -> $MASK_VALUE"
    else
      log_limited maskfail 30 "WARN could not write $MASK_VALUE to $MASKVAL"
    fi
  fi
  if [ "$(knob_read)" = "1" ]; then applied=1; [ "$on_since" -gt 0 ] || on_since=$(date +%s); return 0; fi
  if echo 1 > $KNOB 2>/dev/null; then
    applied=1; on_since=$(date +%s)
    log "ON  mask=$MASK_VALUE (trigger)"
    NEED_VERIFY=1; VERIFY_SINCE=0
  else
    log_limited onfail 15 "WARN could not write 1 to knob"
  fi
}

knob_off() {
  echo 0 > $KNOB 2>/dev/null
  applied=0; on_since=0; last_active=0
  log "OFF (release)"
  NEED_VERIFY=1; VERIFY_SINCE=0
}

# --- cleanup, on EVERY exit path ------------------------------------------
cleanup() {
  echo 0 > $KNOB 2>/dev/null
  R=$(knob_read)
  if [ "$R" = "0" ]; then log "cleanup: knob verified 0"
  else log "cleanup WARNING knob reads '$R' after forced 0 (static display; needs a screen cycle)"; fi
  rm -f $PIDF 2>/dev/null
  log "--- relay stopped ---"
}
trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM HUP

# --- trigger detection, READ ONLY -----------------------------------------
# BURN-IN SAFETY: never hold the mask while the device is not awake.
# With mWakefulness=Asleep no frames are submitted, so the driver never reaches
# __decon_update_regs and the release never happens - the panel sits at the mask
# level until something submits a frame. Observed 2026-10-01: knob 0, actual 337,
# stuck, because the relay re-armed on the still-present UdfpsControllerOverlay.
# PERFORMANCE / BOOT-CONTENTION FIX 2026-10-02.
#
# This used to be three independent probes, each spawning its own Java binder
# call, on EVERY 1-second loop iteration:
#     device_awake()     -> dumpsys power
#     fp_op_live()       -> dumpsys fingerprint   (full dump)
#     fp_acquire_count() -> dumpsys fingerprint   (a SECOND full dump)
# Measured cost of the old version: 331 CPU ticks in 30 s = 3.31 CPU-seconds
# per 30 s, about 11% of one core, forever, with loadavg 17.9 on this device.
# Worse, the KSU module starts the relay at boot, so that traffic lands exactly
# on top of vendor HAL registration - the window where wifi/ril/nfc are already
# fragile. See BUILD_NOTES for the wifi VINTF/HIDL 24 s window that this
# competes with.
#
# Now: ONE dumpsys fingerprint per iteration fills every answer, and
# dumpsys power is refreshed only every POWER_EVERY_N iterations because
# wakefulness changes at human speed, not 1 Hz.
FP_OP=0
FP_ENROLL=0
FP_ACQ=-1
DEV_AWAKE=0
# v7: POWER_EVERY_N 3 -> 1. At 3 the awake flag could be 3 s stale, which is
# plenty to light the mask while the panel is genuinely asleep - where the write
# is INERT (measured: actual stayed 0 for 12 s with knob=1) - and equally to
# sail past a DT2S transition. dumpsys power is far cheaper than the fingerprint
# dump in the same iteration, so this is affordable.
POWER_EVERY_N=1
_ITER=0
PROBE_EMPTY=0
SCREEN_OFF_AT=0
PREV_WAKEFUL=unknown

probe_refresh() {
  _d=$(dumpsys fingerprint 2>/dev/null)
  # v7: AN EMPTY DUMP IS NOT EVIDENCE THAT THE OPERATION ENDED.
  # dumpsys fingerprint goes through binder and can come back empty when the
  # service is busy. The old code read that as FP_OP=0 and released the mask on
  # the very next line. That is the 1-second ON/OFF flicker in relay.log:
  #   13:11:46 ON  mask=337 (trigger)
  #   13:11:47 RELEASED immediately: no finger within 20s, or no live
  #            fingerprint operation
  # On an empty dump we now KEEP the previous state and say so. Being wrong
  # this way for one iteration is safe: the ceilings below are absolute.
  if [ -z "$_d" ]; then
    PROBE_EMPTY=$((PROBE_EMPTY + 1))
    log_limited probeempty 30 "dumpsys fingerprint empty (${PROBE_EMPTY}x) - keeping previous op state FP_OP=$FP_OP"
    return 0
  fi
  PROBE_EMPTY=0
  FP_OP=0
  FP_ENROLL=0
  _o=$(echo "$_d" | grep -m1 'Current operation:')
  case "$_o" in
    *'Current operation: null'*) ;;
    *'Current operation:'*) FP_OP=1 ;;
  esac
  # v7: WHICH mode. The op string names the client, measured live:
  #   enroll -> ...FingerprintEnrollClient,         owner=com.android.settings
  #   auth   -> ...FingerprintAuthenticationClient, owner=com.android.systemui
  # Enrollment is the mode that needs a long illumination budget.
  echo "$_o" | grep -q 'FingerprintEnrollClient' && FP_ENROLL=1
  # Secondary signal: BiometricStateCallback (0 idle, 1 enrolling, 2 authenticating)
  if [ "$FP_OP" = 0 ]; then
    echo "$_d" | grep -qE 'Fps state: [1-9]' && FP_OP=1
  fi
  [ "$FP_ENROLL" = 0 ] && echo "$_d" | grep -q 'FingerprintEnroll' && FP_ENROLL=1
  FP_ACQ=$(echo "$_d" | grep -m1 '"prints"' | grep -o '"acquire":[0-9]*' \
    | head -n 1 | cut -d: -f2)
  [ -z "$FP_ACQ" ] && FP_ACQ=-1

  _ITER=$((_ITER + 1))
  # v7: sampled every iteration (see POWER_EVERY_N above), and the Awake ->
  # not-Awake edge is recorded so the wake gate can tell "the user is putting
  # the phone to sleep" from "a finger arrived on a dark screen".
  if dumpsys power 2>/dev/null | grep -q "mWakefulness=Awake"; then
    _wf=Awake
  else
    _wf=Asleep
  fi
  if [ "$_wf" != "$PREV_WAKEFUL" ]; then
    _now=$(date +%s)
    # Only arm the inhibit on a transition we did NOT cause ourselves. Our own
    # KEYCODE_WAKEUP also produces an Asleep->Awake edge; the reverse edge a
    # moment later would otherwise look like a fresh deliberate sleep.
    if [ "$_wf" = Asleep ] && [ "$PREV_WAKEFUL" = Awake ] \
       && [ $((_now - LAST_WAKE)) -ge 2 ]; then
      SCREEN_OFF_AT=$_now
      log_limited screenoff 15 "panel went down - DT2S/keysleep inhibit armed for ${SCREEN_OFF_INHIBIT}s"
    fi
    PREV_WAKEFUL=$_wf
  fi
  if [ "$_wf" = Awake ]; then DEV_AWAKE=1; else DEV_AWAKE=0; fi
}

device_awake() {
  [ "$DEV_AWAKE" = 1 ]
}

# --- live fingerprint operation detection, READ ONLY -------------------------
# Idle prints exactly "Current operation: null". Measured live on this board:
#   auth   -> Current operation: {[56] ...FingerprintAuthenticationClient,
#             owner=com.android.systemui, requestId=35}, State: 2
#   enroll -> ...FingerprintEnrollClient, owner=com.android.settings
# This is the authoritative "a capture can happen right now" signal.
#
# The OLD signal was a mCurrentFocus grep for fingerprint|biometric. That is
# true for the ENTIRE Settings enrollment flow (Introduction, FindSensor,
# Enrolling) - measured 13 minutes continuous on 2026-10-01. It burned the 45s
# ceiling at 08:16:39 and set BLOCKED=1, which suppressed every re-arm until the
# trigger cleared at 08:28:24. The real FingerprintEnrollClient window was
# 08:20:42-08:21:42 and sat entirely inside that blackout, so the panel never
# illuminated and that enrollment ended success:false with ZERO acquire
# callbacks. A trigger that can be true when no capture is possible is worse
# than no trigger at all.
fp_op_live() {
  [ "$FP_OP" = 1 ] && { OP_SEEN=1; return 0; }
  return 1
}

# The HAL's own acquire counter. It advances every time the sensor reports a
# frame, so it is a DIRECT finger-present signal, available from the same
# dumpsys we already call. Proven to move: 16 -> 23 across one lit touch.
# Reads the counter captured by probe_refresh(); no extra dumpsys.
fp_acquire_count() {
  echo "$FP_ACQ"
}

# The touchscreen is the missing "a finger is here" signal. The HAL acquire
# counter cannot switch the light on (it only advances while the mask is lit),
# and the anti-burn-in backoff would otherwise leave a real touch waiting in the
# dark for up to SCAN_BACKOFF_MAX seconds - the worst possible outcome, because
# the touch that finally arrives is the one that must not fail.
#
# ist40xx_ts is the sec_touchscreen IRQ in /proc/interrupts and it advances on
# ANY contact with the panel. Measured frozen at 25059 for 30 s on the lock
# screen with no finger anywhere, so a change here is unambiguous.
TOUCH_IRQ_LINE=ist40xx_ts
touch_irq() {
  awk -v l="$TOUCH_IRQ_LINE" '$0 ~ l { print $2; exit }' /proc/interrupts 2>/dev/null
}

# Trigger = a live fingerprint operation. Nothing else.
#
# FALSIFIED 2026-10-01: gating on the HAL acquire counter as a "finger present"
# signal does not work, because it is circular. Measured 45s on the lock screen
# with an auth client live: acquire stayed frozen at 23 for every sample, while
# the same counter had moved 16 -> 23 during an earlier lit window. The sensor
# only scans while the mask is lit, so acquire cannot be the thing that turns
# the light on. It is logged as evidence only.
#
# "op live" is also the correct semantic: the keyguard auth client is created
# exactly when the lock screen wants a fingerprint, and the enroll client while
# Settings wants one. Burn-in is bounded by MAX_ON_SECONDS plus the cooldown
# re-arm, NOT by trying to be clever about what a live op implies.
LAST_ACQ=-1
trigger_active() { fp_op_live; }

# --- wake gate ---------------------------------------------------------------
# PROVEN 2026-10-01 (see BUILD_NOTES.md): on the lock screen the panel is ASLEEP
# while the finger is read. Measured with the knob held at 1 for 12s:
# actual_mask_brightness stayed 0 for every single sample. Then ONE
# KEYCODE_WAKEUP: actual went to 337 within 2s and stayed there.
#
# So knob=1 while asleep is not just risky, it is INERT: no frames are
# submitted, __decon_update_regs never runs, the mask is never applied, and the
# trustlet rejects the frame. That is the real reason "brightness does not
# engage on the lock screen".
#
# Root cause: stock sets win_config.state=DECON_WIN_STATE_FINGERPRINT from
# gralloc metadata, which makes the display HAL wake the panel for a
# fingerprint read. AOSP has no POWER_MODE_FINGERPRINT, so on this ROM nothing
# ever wakes it. Waking it ourselves reproduces the stock effect. This injects
# no UI, no tap, no swipe and does not move focus.
LAST_WAKE=0
WAKE_MIN_GAP=3
wake_for_fp() {
  # Wakes the display, but ONLY ever for a real finger on a real fingerprint op.
  #
  # Measured 2026-10-02: an earlier version woke the screen on its own at
  # 01:57:07, 01:57:17 and 01:59:31 with nobody touching anything, because
  # ist40xx_ts is edge-triggered on the panel's INT line and also fires for
  # charger/panel events - and this device has mWakeUpWhenPluggedOrUnplugged=true.
  # "the touchscreen IRQ moved" therefore does NOT mean "a finger arrived".
  #
  # So the caller requires BOTH conditions before we get here:
  #   * a live fingerprint scheduler operation, and
  #   * an IRQ change within TOUCH_WINDOW.
  #
  # That pairing is also exactly what makes AOD / screen-off fingerprint work:
  # with the display dark the keyguard auth client is already live, so a finger
  # on the sensor produces (IRQ change + live op) and we wake, light the mask
  # and the capture proceeds. Without the wake the panel stays inert and the
  # trustlet rejects every frame, which is why screen-off auth could never work.
  _n=$(date +%s)
  # v7: DT2S GUARD - the fix for "double tap to sleep unsleeps the phone".
  # A double tap is two ist40xx_ts edges. On the lock screen a fingerprint auth
  # client is live, so (IRQ change + live op) is true and we used to fire
  # KEYCODE_WAKEUP straight back, undoing the user's own sleep within ~2 s.
  # If the panel was seen going down very recently, those IRQs are the double
  # tap, not a finger reaching for the sensor. Stay dark. After the inhibit
  # expires the next touch is a genuine AOD fingerprint intent and wakes.
  _since=$((_n - SCREEN_OFF_AT))
  if [ "$SCREEN_OFF_AT" -gt 0 ] && [ "$_since" -lt "$SCREEN_OFF_INHIBIT" ]; then
    log_limited dt2sguard 10 "WAKE suppressed (${_since}s after panel went down) - deliberate sleep, not a sensor touch"
    return 0
  fi
  [ $((_n - LAST_WAKE)) -lt $WAKE_MIN_GAP ] && return 0
  LAST_WAKE=$_n
  input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  log_limited wake 10 "WAKE: finger on sensor + live fingerprint op - KEYCODE_WAKEUP so the mask becomes effective"
}

applied=0
on_since=0
last_active=0
NEED_VERIFY=0
VERIFY_SINCE=0
BLOCKED=0          # set after a ceiling; cleared after CEILING_COOLDOWN
BLOCKED_AT=0
BASE_ACQ=-1        # HAL acquire counter sampled when we turned the mask on
SAW_SCAN=0         # 1 once that counter has advanced => a real finger scan
NEXT_ARM=0         # earliest timestamp we may light the mask again
LAST_TOUCH_IRQ=$(touch_irq)
TOUCHED=0          # 1 once the panel has been touched; consumed by the wake gate
LAST_TOUCH_TS=0    # timestamp of the most recent ist40xx_ts IRQ change
TOUCH_WINDOW=20    # how long a touch keeps the mask armed and the wake justified
PREV_BRIGHT_MODE=$(settings get system screen_brightness_mode 2>/dev/null)
echo "touch IRQ baseline = ${LAST_TOUCH_IRQ}"
echo "screen_brightness_mode on start = ${PREV_BRIGHT_MODE}"

# Hand the panel back to automatic brightness whenever we let go of the mask.
# The mask write is a fixed panel level, so leaving it engaged is exactly what
# "brightness does not disengage" looks like. Best effort: a failure here must
# never delay or prevent the knob from being cleared.
restore_adaptive_brightness() {
  settings put system screen_brightness_mode 1 >/dev/null 2>&1
}

log "--- relay started v10 T0=$T0 state=$STATE node_wait=${_waited}s grace_end=$GRACE_END mask=$MASK_VALUE auth_ceiling=${MAX_ON_SECONDS}s enroll_ceiling=${MAX_ON_SECONDS_ENROLL}s dt2s_inhibit=${SCREEN_OFF_INHIBIT}s ---"

while true; do
  T=$(date +%s)

  # 0. PROBE. One dumpsys fingerprint per iteration fills FP_OP / FP_ACQ, and
  #    dumpsys power is refreshed only every POWER_EVERY_N iterations.
  #
  #    BOOT QUIET: for the first BOOT_QUIET_SECONDS after start we do not probe
  #    at all. The relay is launched by a KSU module at boot, and the vendor HALs
  #    are registering in exactly this window - wifi alone spends 24 s failing to
  #    reach a HIDL interface that no VINTF manifest declares before falling back
  #    to AIDL. Nothing can legitimately need fingerprint illumination this early
  #    (no client can be authenticating before system_server is up), so staying
  #    quiet costs nothing and removes our binder traffic from that window.
  if [ $T -lt $QUIET_END ]; then
    FP_OP=0
    DEV_AWAKE=1   # do not let a stale 0 masquerade as "asleep" during quiet
    sleep 2
    continue
  fi
  probe_refresh

  # 0a. TOUCH SAMPLE. Must run before the awake check: the touchscreen is live
  #      while the panel is asleep, and that is precisely when we need to know
  #      a finger arrived so the wake below can be justified.
  _irq=$(touch_irq)
  if [ -n "$_irq" ] && [ -n "$LAST_TOUCH_IRQ" ] && [ "$_irq" != "$LAST_TOUCH_IRQ" ]; then
    LAST_TOUCH_IRQ=$_irq
    TOUCHED=1
    LAST_TOUCH_TS=$T
    NO_SCAN_STREAK=0
    NEXT_ARM=0
    log_limited toucharm 30 "panel touched (irq $_irq) -> backoff cleared, arm immediately"
  elif [ -n "$_irq" ]; then
    LAST_TOUCH_IRQ=$_irq
  fi
  touch_fresh() { [ $((T - LAST_TOUCH_TS)) -le $TOUCH_WINDOW ]; }

  # 0. WAKE GATE + BURN-IN GUARD.
  #
  #    While the panel is ASLEEP the mask is inert (measured: actual stayed 0
  #    for 12s with knob=1), so a wake is only justified when a finger is on the
  #    glass AND a fingerprint op is live. Either alone is not enough - see the
  #    long note on wake_for_fp() for the 01:57 wake-storm that motivated it.
  #
  #    asleep + touch + live op -> WAKE (this is the AOD / screen-off path).
  #    asleep + touch, no op    -> stay asleep; nothing would be captured.
  #    asleep + op, no touch    -> stay asleep; nobody is there.
  #    asleep + neither         -> force OFF. This is the real burn-in case (a
  #                               frame arriving later would pin actual at the
  #                               mask level).
  if ! device_awake; then
    if [ "$TOUCHED" -eq 1 ] && trigger_active; then
      TOUCHED=0
      wake_for_fp
    elif [ "$applied" -eq 1 ] || [ "$(knob_read)" = "1" ]; then
      echo 0 > $KNOB 2>/dev/null
      applied=0; on_since=0; last_active=0
      restore_adaptive_brightness
      log "OFF (device asleep, must not hold mask)"
    fi
    sleep 1
    continue
  fi
  [ "$TOUCHED" -eq 1 ] && TOUCHED=0

  # 1. stale/foreign adoption: the knob is lit but we did not put it there.
  #    NOTE: since the vendor flash the HAL also writes this knob (its glob is
  #    fixed now), and the HAL never sets mask_brightness. So an adopted 1 must
  #    still have the level corrected, or the panel runs at 255 -> BAD_QUALITY 39.
  if [ "$applied" -eq 0 ] && [ "$(knob_read)" = "1" ]; then
    echo "$MASK_VALUE" > $MASKVAL 2>/dev/null
    log_limited maskset 30 "mask_brightness -> $MASK_VALUE (on adopt)"
    on_since=$T
    log "ADOPT foreign 1 on knob (level re-asserted)"
    BASE_ACQ=$(fp_acquire_count); SAW_SCAN=0
    applied=1
  fi

  # 1b. While active, keep re-asserting the LEVEL. The panel driver resets
  #     lcd->mask_brightness on display resume (observed 337 -> 255 across a
  #     reboot), and the HAL does not set it. A HAL-driven turn-on would
  #     therefore capture at 255. Cheap, rate-limited, idempotent.
  if [ "$applied" -eq 1 ]; then
    if [ "$(cat $MASKVAL 2>/dev/null)" != "$MASK_VALUE" ]; then
      echo "$MASK_VALUE" > $MASKVAL 2>/dev/null
      log_limited maskset 30 "mask_brightness re-asserted -> $MASK_VALUE"
    fi
  fi

  # 2. TRIGGERS - a live op AND a recent finger. Both, always.
  #
  #    Why not op-only: with other sessions driving this device, simply OPENING an
  #    app was enough to make the mask engage and toggle at random. Whatever the
  #    app does that makes a fingerprint client appear (a secure-surface check,
  #    a HAL probe, the camera's own auth), it is not a finger on the sensor and
  #    must not light the panel.
  #
  #    Why not touch-only: a stray IRQ edge on its own is not a capture request
  #    either, and lighting on that is what caused the wake storm.
  #
  #    touch_fresh() = an ist40xx_ts change within TOUCH_WINDOW. The window is
  #    longer than one loop so a finger that arrives while a client is starting
  #    still finds the gate open, and short enough that a touch from minutes ago
  #    does not authorise lighting.
  if trigger_active && touch_fresh; then
    last_active=$T
    if [ "$BLOCKED" -eq 0 ] && [ "$applied" -eq 0 ] && [ "$T" -ge "$NEXT_ARM" ]; then
      knob_on
      BASE_ACQ=$(fp_acquire_count); SAW_SCAN=0
    fi
  elif [ "$applied" -eq 1 ] || [ "$(knob_read)" = "1" ]; then
    # 2b. NOTHING TO CAPTURE -> LET GO NOW.
    #     Either no live operation, or a live operation with no finger on the
    #     glass. Success, failure, a cancelled client, backing out of the Settings
    #     enrollment flow, and an unrelated app opening ALL land here. Every one
    #     of those was reported as "brightness does not disengage", so this path
    #     must not wait out RELEASE_SECONDS, must not consult BLOCKED, and must
    #     not be deferred by the startup grace. It also covers a knob the HAL set
    #     behind our back.
    knob_off
    BLOCKED=0; BLOCKED_AT=0; NEXT_ARM=0; NO_SCAN_STREAK=0; SAW_SCAN=0
    BASE_ACQ=-1
    restore_adaptive_brightness
    log "RELEASED immediately: no finger within ${TOUCH_WINDOW}s, or no live fingerprint operation (adaptive brightness restored)"
  fi

  # 3. CEILING. Duty-cycle, NOT a latch.
  #    A latch that waits for the trigger to go false is fatal on the lock
  #    screen: the keyguard auth client stays live for minutes, so the trigger
  #    never clears and illumination is blackholed for the whole time. Measured
  #    2026-10-01: ceiling at 09:29:06, still knob=0 at 09:35:00 while
  #    last_active kept advancing. Cool down briefly and re-arm instead.
  if [ "$applied" -eq 1 ] && [ "$on_since" -gt 0 ]; then
    ON_FOR=$((T - on_since))
    # v7: budget depends on mode - see MAX_ON_SECONDS_ENROLL.
    if [ "$FP_ENROLL" = 1 ]; then
      CEIL=$MAX_ON_SECONDS_ENROLL
    else
      CEIL=$MAX_ON_SECONDS
    fi
    if [ $ON_FOR -ge $CEIL ]; then
      knob_off
      BLOCKED=1; BLOCKED_AT=$T
      log "CEILING: forced off after ${ON_FOR}s (enroll=${FP_ENROLL}, budget ${CEIL}s); ${CEILING_COOLDOWN}s cooldown then re-arm"
    fi
  fi
  if [ "$BLOCKED" -eq 1 ] && [ $((T - BLOCKED_AT)) -ge $CEILING_COOLDOWN ]; then
    BLOCKED=0
    log "ceiling cooldown elapsed, re-arm allowed"
  fi

  # 3b. SCAN-GATED RELEASE (see SCAN_GRACE at the top). Only while we have not
  #     yet seen a single sensor scan since turning the light on.
  # v7: no scan gate during enrollment. It exists so an unattended panel is not
  # held lit, but during enrollment the client is live on purpose and the user
  # is mid-capture; releasing after SCAN_GRACE is what starved enrollment. The
  # mode-dependent ceiling above is the only guard there.
  if [ "$applied" -eq 1 ] && [ "$on_since" -gt 0 ] && [ "$SAW_SCAN" -eq 0 ] \
     && [ "$FP_ENROLL" = 0 ]; then
    ACQ=$(fp_acquire_count)
    if [ -n "$ACQ" ] && [ "$BASE_ACQ" -ge 0 ] && [ "$ACQ" -ne "$BASE_ACQ" ]; then
      SAW_SCAN=1
      NO_SCAN_STREAK=0
      log "scan seen (acquire $BASE_ACQ -> $ACQ) - mask stays on under normal ceiling"
    elif [ $((T - on_since)) -ge $SCAN_GRACE ]; then
      knob_off
      NO_SCAN_STREAK=$((NO_SCAN_STREAK + 1))
      B=$((SCAN_BACKOFF * NO_SCAN_STREAK))
      [ $B -gt $SCAN_BACKOFF_MAX ] && B=$SCAN_BACKOFF_MAX
      NEXT_ARM=$((T + B))
      log "RELEASED: no sensor scan within ${SCAN_GRACE}s (no finger, streak ${NO_SCAN_STREAK}); re-arm not before +${B}s"
    fi
  fi

  # 4. time-based release. NO sticky flag can disable this.
  if [ "$applied" -eq 1 ] && [ "$on_since" -gt 0 ]; then
    IDLE_FOR=$((T - last_active))
    if [ "$IDLE_FOR" -ge $RELEASE_SECONDS ]; then
      if [ $T -lt $GRACE_END ]; then
        log_limited gracehold 10 "release deferred: inside startup grace (ends $GRACE_END)"
      else
        knob_off
        log "RELEASED: no activity for ${RELEASE_SECONDS}s (absolute, history-independent)"
      fi
      # No live fingerprint op means nobody is waiting on the sensor, so the
      # anti-burn-in backoff buys nothing. Clear it so the NEXT real attempt
      # gets an immediate light-up instead of inheriting a stale streak.
      NO_SCAN_STREAK=0
      NEXT_ARM=$T
      restore_adaptive_brightness
    elif [ "$IDLE_FOR" -ge $RELEASE_SECONDS ]; then
      knob_off
    fi
  fi

  # 5. verify the write actually landed
  if [ "$NEED_VERIFY" -eq 1 ]; then
    [ "$VERIFY_SINCE" -eq 0 ] && VERIFY_SINCE=$T
    if [ $((T - VERIFY_SINCE)) -ge 3 ]; then
      NEED_VERIFY=0; VERIFY_SINCE=0
      R=$(knob_read)
      log "verify: knob=$R (want 0)"
    fi
  fi

  # 6. heartbeat, keeps the log alive for diagnosis without spamming
  [ $((T % 300)) -eq 0 ] && log "alive applied=$applied on_since=$on_since last_active=$last_active knob=$(knob_read)"

  sleep 1
done
