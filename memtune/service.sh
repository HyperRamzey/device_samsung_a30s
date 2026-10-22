#!/system/bin/sh
# service.sh -- re-apply the measured memory tuning, AFTER lmkd, every boot.
#
# WHY late_start and not post-fs-data
#   docs/15 §22.2 measured that lmkd rewrites
#   /sys/module/lowmemorykiller/parameters/minfree on every boot.  A table written from
#   post-fs-data (which runs before lmkd) is therefore simply overwritten.  service.sh is
#   the late_start class, which runs after lmkd has already published its own default
#   table, so the write lands and stays.
#
# WHAT THIS MUST NEVER DO
#   Restart the camera provider.  This shares a module slot with the camera work and a
#   provider restart from late_start would churn the PID and break the
#   "no provider churn" success criterion.  This script only writes sysctls.
#
# THE TRAP THAT SHAPED THE VERIFICATION BELOW (docs/15 §22.2)
#   `echo "12288 16384 ..." > .../minfree` (spaces) zeroed the array, the driver's
#   array_size collapsed to 0, and the in-kernel LMK was silently disabled - only the OOM
#   killer remained, and it took the device an hour to notice.  So: commas only, and the
#   readback is verified; on any mismatch the STOCK table is restored and the failure
#   logged rather than left in a degraded state.

LOG=/data/local/tmp/derp_memtune.log
exec >> "$LOG" 2>&1

MINFREE=/sys/module/lowmemorykiller/parameters/minfree
ADJ=/sys/module/lowmemorykiller/parameters/adj

# the measured, validated set (docs/15 §22.1/§22.3)
WANT_MINFREE="12288,16384,20480,24576,61440,81920"
WANT_ADJ="0,100,200,250,900,950"
WANT_EXTRA_FREE=24576
WANT_VFS_CACHE=150
WANT_PAGE_CLUSTER=3
WANT_ZSWAP_PCT=25

# stock values, used both as the revert target and as the "not mine" sentinel
STOCK_MINFREE="18432,23040,27648,32256,55296,80640"
STOCK_EXTRA_FREE=13162
STOCK_VFS_CACHE=50
STOCK_PAGE_CLUSTER=0
STOCK_ZSWAP_PCT=20

echo "=== derp_memtune $(date) (late_start, after lmkd) ==="

log_node() {
  echo "  $1 = $(cat "$2" 2>/dev/null)"
}

restore_stock() {
  echo "  SAILS-DOWN: restoring the stock table because the write did not take"
  echo "$STOCK_MINFREE" > "$MINFREE" 2>/dev/null
  echo "$STOCK_EXTRA_FREE"  > /proc/sys/vm/extra_free_kbytes 2>/dev/null
  echo "$STOCK_VFS_CACHE"   > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
  echo "$STOCK_PAGE_CLUSTER" > /proc/sys/vm/page-cluster 2>/dev/null
  echo "$STOCK_ZSWAP_PCT"   > /sys/module/zswap/parameters/max_pool_percent 2>/dev/null
}

# --- LMK minfree + adj: the load-bearing pair.  Verify, never assume. ---
[ -w "$MINFREE" ] || { echo "  ABORT: $MINFREE not writable"; restore_stock; exit 1; }
echo "$WANT_MINFREE" > "$MINFREE" 2>/dev/null
GOT=$(cat "$MINFREE" 2>/dev/null)
if [ "$GOT" != "$WANT_MINFREE" ]; then
  echo "  ABORT: minfree read back '$GOT', wanted '$WANT_MINFREE'"
  restore_stock
  exit 1
fi
echo "  minfree OK : $GOT"
echo "$WANT_ADJ" > "$ADJ" 2>/dev/null
GOTA=$(cat "$ADJ" 2>/dev/null)
[ "$GOTA" = "$WANT_ADJ" ] || echo "  WARN: adj read back '$GOTA' (not forced; lmkd owns the default adj)"

# --- sysctls: same discipline, verify each ---
w() { # w <path> <value> <label>
  echo "$2" > "$1" 2>/dev/null
  G=$(cat "$1" 2>/dev/null)
  [ "$G" = "$2" ] || echo "  WARN: $3 read back '$G', wanted '$2'"
}
w /proc/sys/vm/extra_free_kbytes "$WANT_EXTRA_FREE" extra_free_kbytes
w /proc/sys/vm/vfs_cache_pressure  "$WANT_VFS_CACHE"  vfs_cache_pressure
w /proc/sys/vm/page-cluster       "$WANT_PAGE_CLUSTER" page-cluster
w /sys/module/zswap/parameters/max_pool_percent "$WANT_ZSWAP_PCT" zswap_max_pool_percent

echo "  --- effective ---"
log_node extra_free_kbytes /proc/sys/vm/extra_free_kbytes
log_node vfs_cache_pressure /proc/sys/vm/vfs_cache_pressure
log_node page-cluster /proc/sys/vm/page-cluster
log_node min_free_kbytes /proc/sys/vm/min_free_kbytes
log_node zswap_max_pool_percent /sys/module/zswap/parameters/max_pool_percent
log_node compact_unevictable_allowed /proc/sys/vm/compact_unevictable_allowed

# --- report what the #214 lmk-bp gives us, so a degraded build is visible ---
echo "  --- lmk-bp backport (kernel #214) ---"
log_node kill_interval_ms /sys/module/lowmemorykiller/parameters/kill_interval_ms
if [ -f /proc/lmkd_debug/lmkd_count ]; then
  echo "  /proc/lmkd_debug present: YES"
else
  echo "  /proc/lmkd_debug present: NO  (kernel is NOT #214+ -- the tuned table alone gives the kill storm back, see docs/15 §22.3)"
fi

# --- never let this be mistaken for a provider touch ---
PROVIDER=android.hardware.camera.provider@2.5-service.exynos7885
echo "  camera provider (untouched): [$(pidof $PROVIDER 2>/dev/null)]"

echo "=== derp_memtune done ==="
