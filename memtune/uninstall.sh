#!/system/bin/sh
# uninstall.sh -- restore the stock memory table.
#
# The goal is to leave the device exactly where it was, and to do it safely: the
# §22.2 trap (space-separated minfree write zeroes the array and silently disables the
# in-kernel LMK) means a bad write is worse than no write, so the table is written with
# commas and verified against the stock value.

LOG=/data/local/tmp/derp_memtune.log
exec >> "$LOG" 2>&1

MINFREE=/sys/module/lowmemorykiller/parameters/minfree
STOCK_MINFREE="18432,23040,27648,32256,55296,80640"

echo "=== uninstall $(date): restoring the stock memory table ==="

if [ -w "$MINFREE" ]; then
  echo "$STOCK_MINFREE" > "$MINFREE" 2>/dev/null
  GOT=$(cat "$MINFREE" 2>/dev/null)
  if [ "$GOT" = "$STOCK_MINFREE" ]; then
    echo "  minfree restored to $GOT"
  else
    echo "  WARN: minfree reads '$GOT', wanted '$STOCK_MINFREE' - RELOADING lmkd's own default"
    # lmkd publishes the default table from ro.lmk.minfree_levels on every boot, so
    # restarting it is the guaranteed way back to stock values.
    setprop ctl.restart lmkd
    sleep 2
    echo "  minfree now: $(cat "$MINFREE" 2>/dev/null)"
  fi
else
  echo "  $MINFREE not writable - nothing to do"
fi

echo 13162 > /proc/sys/vm/extra_free_kbytes 2>/dev/null
echo 50    > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
echo 0     > /proc/sys/vm/page-cluster 2>/dev/null
echo 20    > /sys/module/zswap/parameters/max_pool_percent 2>/dev/null

echo "  --- restored state ---"
for n in extra_free_kbytes vfs_cache_pressure page-cluster; do
  echo "  $n = $(cat /proc/sys/vm/$n 2>/dev/null)"
done
echo "  zswap_max_pool_percent = $(cat /sys/module/zswap/parameters/max_pool_percent 2>/dev/null)"
echo "  $MINFREE = $(cat "$MINFREE" 2>/dev/null)"
echo "=== uninstall done ==="
