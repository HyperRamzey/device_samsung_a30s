#!/system/bin/sh
# Google Photos first-boot install (config-split APK set).
#
# Google Photos is published only as an Android App Bundle: its base APK declares
#   android:requiredSplitTypes="base__abi,base__density"
# and the values of many base-APK resources were moved by bundletool into the
# config splits. A base APK alone therefore has HOLES in its own resource table.
# Measured on the previously shipped /system/app/GooglePhotos/GooglePhotos.apk
# (7.94.0.984908898, flattened base + arm64 split, 152,994,692 B):
#   drawable/photos_tabbar_photos_icon = 0x7f08090c -> res/prx.xml, whose two
#   android:drawable items reference @0x7f08090b and @0x7f080ac7 - neither id is
#   defined anywhere in that APK's resources.arsc (aapt2 dump resources prints
#   0x7f080900..0x7f08090a, skips 0x7f08090b, prints 0x7f08090c...).
# Launch result on device, every time:
#   AndroidRuntime: Resources$NotFoundException: Drawable
#     com.google.android.apps.photos:drawable/photos_tabbar_photos_icon #0x7f08090c
#   Caused by: ... File res/prx.xml from drawable resource ID #0x7f08090c
# A system install cannot carry config splits: Soong has no support for them in
# android_app_import (build/soong/java/app_import.go:414 "TODO: LOCAL_PACKAGE_SPLITS"),
# and `pm install` of the base alone is refused with
#   INSTALL_FAILED_MISSING_SPLIT: Missing split for com.google.android.apps.photos
#
# Fix: ship the base APK plus the config splits this device needs, and install
# them as one multi-package session at first boot - the same thing Play does.
# Google's own signature is preserved, so Play can update the app later.
#
# Runs in the shell domain (user shell + seclabel u:r:shell:s0), the same
# uid/domain the proven agc_boot_update.sh uses for `pm install`. Log:
# /data/local/tmp/derp_gphotos_install.log
# Evidence and decision record: docs/projects/PHOTOS-APP.md

LOG=/data/local/tmp/derp_gphotos_install.log
PKG=com.google.android.apps.photos
DIR=/system/etc/derp-gphotos
# These are the installed names of the four prebuilt_etc modules declared in
# device/samsung/a30s/gphotos/Android.bp. Soong installs a prebuilt_etc under its
# module name unless filename_from_source is set, so the names here are the module
# names, verified against the built image (ls /system/etc/derp-gphotos after an
# fsck.erofs --extract of system.raw.img).
APKS="derp_gphotos_base derp_gphotos_split_arm64_v8a derp_gphotos_split_xxxhdpi derp_gphotos_split_en"

now() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(now) derp-gphotos-install: $*" >>"$LOG" 2>/dev/null; }

p="$(pm path $PKG 2>/dev/null | head -n1)"
log "enter (path=$p)"

case "$p" in
  package:/data/app/*)
    log "already installed as a data package ($p); nothing to do"
    exit 0
    ;;
  package:*)
    # A preinstalled copy would be the broken flattened APK. Do not try to
    # install over it: a different signer is rejected outright
    # (INSTALL_FAILED_UPDATE_INCOMPATIBLE), and the tree no longer ships one.
    log "unexpected package state ($p); not touching"
    exit 1
    ;;
  "")
    ;;
esac

PATHS=""
for f in $APKS; do
  if [ ! -f "$DIR/$f" ]; then
    log "split APK missing: $DIR/$f"
    exit 1
  fi
  PATHS="$PATHS $DIR/$f"
done

# One session, all splits at once. PMS validates that every APK shares the
# signer and that the required split types (base__abi, base__density) are covered.
# $PATHS is deliberately unquoted: it is a whitespace-separated list of absolute
# paths that must split into one argument per APK (SC2086 is intentional).
# shellcheck disable=SC2086
pm install -r $PATHS >>"$LOG" 2>&1
rc=$?
log "pm install rc=$rc (path=$(pm path $PKG 2>/dev/null | head -n1))"

if [ "$rc" -eq 0 ]; then
  # Best-effort grants so the first launch needs fewer prompts. Permissions the
  # app does not declare fail harmlessly (|| true).
  for perm in \
      android.permission.READ_MEDIA_IMAGES \
      android.permission.READ_MEDIA_VIDEO \
      android.permission.READ_MEDIA_VISUAL_USER_SELECTED \
      android.permission.POST_NOTIFICATIONS; do
    pm grant $PKG $perm >/dev/null 2>&1 || true
  done
  log "pre-grants done"
fi
exit "$rc"
