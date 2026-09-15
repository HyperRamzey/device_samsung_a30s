#!/system/bin/sh
# dolby_f5.sh - mount the in-tree Fold5 DAP stack over stock vendor paths.
#
# Runs once from init at post-fs-data (BEFORE the audio HAL starts), so no
# service restart is ever needed. Effect on/off is the stock QS tile
# (org.lineageos.dap), which toggles the DAP AudioEffect live, like stock.
#
# Opt out (stock stack back): touch /data/dolby_f5/disabled + reboot.
#
# Modes: mount (default) | umount (manual testing) | status
#
# Provenance: stage+chcon+overlay+bind mechanics ran live on this device
# (module era + manual in-tree-script runs): overlay mirrors Hybrid Mount's
# own ro lowerdir-only shape over /vendor/lib; views expose vendor_file /
# vendor_configs_file labels the hal_audio domain requires.

SYS=/system/dolby_f5
STG=/data/dolby_f5/stage
LOG=/data/dolby_f5/dolby_f5.log
FLAG_OFF=/data/dolby_f5/disabled

OVL_LIB_DST=/vendor/lib
XML_DST=/vendor/etc/dolby/dax-default.xml
BIN_DST=/vendor/firmware/dax_param.bin

LIB_RELS="lib/soundfx/libswdap.so lib/libprofileparamstorage.so lib/libspatializerparamstorage.so lib/libsecaudiocoreutils.so"

log() {
    echo "$(date '+%m-%d %H:%M:%S') dolby_f5[$1]: $2" >> "$LOG"
}

is_mounted() {
    grep -q " $1 " /proc/mounts 2>/dev/null
}

ensure_stage() {
    mkdir -p "$STG/lib/soundfx" "$STG/lib" "$STG/etc/dolby" "$STG/firmware" 2>/dev/null
    for rel in $LIB_RELS etc/dolby/dax-default.xml firmware/dax_param.bin; do
        src="$SYS/$rel"
        dst="$STG/$rel"
        if [ ! -f "$src" ]; then
            log "stage" "MISSING SOURCE $src"
            return 1
        fi
        if [ ! -f "$dst" ] || [ "$(wc -c < "$src" 2>/dev/null)" != "$(wc -c < "$dst" 2>/dev/null)" ]; then
            cp -f "$src" "$dst" 2>/dev/null || { log "stage" "COPY FAIL $rel"; return 1; }
            log "stage" "staged $rel"
        fi
        case "$rel" in
            *.xml) chcon u:object_r:vendor_configs_file:s0 "$dst" 2>/dev/null ;;
            *)     chcon u:object_r:vendor_file:s0 "$dst" 2>/dev/null ;;
        esac
    done
    return 0
}

mode_mount() {
    if [ -f "$FLAG_OFF" ]; then
        log "mount" "opt-out flag present, staying stock"
        return 0
    fi
    ensure_stage || { log "mount" "STAGE FAILED, aborting"; return 1; }
    changed=0
    if ! is_mounted "$OVL_LIB_DST"; then
        if mount -t overlay overlay -o "ro,lowerdir=$STG/lib:/vendor/lib" "$OVL_LIB_DST" 2>/dev/null; then
            log "mount" "OVERLAY $OVL_LIB_DST (lowerdir=$STG/lib)"
            changed=1
        else
            log "mount" "OVERLAY FAIL $OVL_LIB_DST"
        fi
    fi
    if ! is_mounted "$XML_DST"; then
        if mount --bind "$STG/etc/dolby/dax-default.xml" "$XML_DST" 2>/dev/null; then
            log "mount" "BOUND $XML_DST"
            changed=1
        else
            log "mount" "BIND FAIL $XML_DST"
        fi
    fi
    if ! is_mounted "$BIN_DST"; then
        if mount --bind "$STG/firmware/dax_param.bin" "$BIN_DST" 2>/dev/null; then
            log "mount" "BOUND $BIN_DST"
            changed=1
        else
            log "mount" "BIND FAIL $BIN_DST"
        fi
    fi
    # If mounts landed while audio is already running (late trigger timing),
    # restart the stack so the HAL picks up the F5 blobs. Pre-HAL timing
    # (post-fs-data) skips this: nothing is running yet.
    if [ "$changed" = "1" ]; then
        if [ "$(getprop init.svc.audioserver 2>/dev/null)" = "running" ]; then
            log "mount" "audio running, restarting stack to pick up F5 blobs"
            setprop ctl.restart vendor.audio-hal 2>/dev/null
            sleep 1
            setprop ctl.restart audioserver 2>/dev/null
        else
            log "mount" "done pre-audio-start, no restart needed"
        fi
    else
        log "mount" "already mounted, no-op"
    fi
}

mode_umount() {
    for dst in "$BIN_DST" "$XML_DST" "$OVL_LIB_DST"; do
        if is_mounted "$dst"; then
            if umount "$dst" 2>/dev/null; then
                log "umount" "CLEARED $dst"
            elif umount -l "$dst" 2>/dev/null; then
                log "umount" "LAZY-CLEARED $dst"
            else
                log "umount" "UMOUNT FAIL $dst"
            fi
        fi
    done
}

mode_status() {
    if [ -f "$FLAG_OFF" ]; then
        echo "opt-out flag present (stock)"
    else
        echo "opt-out flag absent (F5 stack active when mounted)"
    fi
    for dst in "$OVL_LIB_DST" "$XML_DST" "$BIN_DST"; do
        if is_mounted "$dst"; then
            echo "MOUNTED $dst"
        else
            echo "stock   $dst"
        fi
    done
    md5sum /vendor/lib/soundfx/libswdap.so /vendor/lib/libspatializerparamstorage.so /vendor/etc/dolby/dax-default.xml /vendor/firmware/dax_param.bin 2>&1
}

case "$1" in
    umount) mode_umount ;;
    status) mode_status ;;
    *)      mode_mount ;;
esac
