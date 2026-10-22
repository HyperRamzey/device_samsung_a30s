#!/system/bin/sh
# AGC (com.samsung.android.ruler) first-boot self-update.
#
# The AGC build is protected by PairIP: its libpairipcore SIGSEGVs
# (SEGV_ACCERR) whenever the APK runs from the /system install context.
# Verified 2026-10-21 on this ROM: identical APK bytes
# (patched build a91c9581) install and run fine once PackageManager records
# an UPDATE of the system package (code + extracted libs under /data/app),
# and crash 100% of the time as the bare /system install - with or without a
# fresh oat in /data/dalvik-cache, with or without an extracted
# /system/app/AGC/lib/arm64.
#
# Fix: at first boot on a clean /data, reinstall the very same APK over
# itself: `pm install -r /system/app/AGC/AGC.apk`. PMS then serves the
# package from /data/app and the app runs. On every later boot the package
# already resolves to /data/app and this script exits 0, so the cost is one
# install per clean /data. If an update install ever fails, the next boot
# retries because the package still resolves to /system/app/AGC.
#
# Runs in the shell domain (user shell + seclabel u:r:shell:s0) -
# mechanically identical to adb shell, which is exactly the uid/domain that
# `pm install` was proven under. Log: /data/local/tmp/agc_boot_update.log
# Evidence and decision record: docs/projects/CAMERA_CAPTURE_STALL.md

LOG=/data/local/tmp/agc_boot_update.log
PKG=com.samsung.android.ruler
SRC=/system/app/AGC/AGC.apk

now() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(now) agc_boot_update: $*" >>"$LOG" 2>/dev/null; }

p="$(pm path $PKG 2>/dev/null | head -n1)"
log "enter (path=$p)"

case "$p" in
  package:/data/app/*)
    log "already updated ($p); nothing to do"
    exit 0
    ;;
  package:/system/app/AGC/AGC.apk|"package:$SRC")
    ;;
  "")
    log "package not found; not touching"
    exit 1
    ;;
  *)
    log "unexpected package state ($p); not touching"
    exit 1
    ;;
esac

if [ ! -f "$SRC" ]; then
  log "source APK missing: $SRC"
  exit 1
fi

pm install -r "$SRC" >>"$LOG" 2>&1
rc=$?
log "pm install rc=$rc (path=$(pm path $PKG 2>/dev/null | head -n1))"

if [ "$rc" -eq 0 ]; then
  # Best-effort runtime pre-grants so the first launch needs no prompts.
  # Non-runtime permissions fail harmlessly (|| true).
  for perm in \
      android.permission.CAMERA \
      android.permission.RECORD_AUDIO \
      android.permission.ACCESS_FINE_LOCATION \
      android.permission.ACCESS_COARSE_LOCATION \
      android.permission.READ_MEDIA_IMAGES \
      android.permission.READ_MEDIA_VIDEO \
      android.permission.READ_EXTERNAL_STORAGE \
      android.permission.WRITE_EXTERNAL_STORAGE \
      android.permission.HIGH_SAMPLING_RATE_SENSORS; do
    pm grant $PKG $perm >/dev/null 2>&1 || true
  done
  log "pre-grants done"
fi
exit "$rc"
