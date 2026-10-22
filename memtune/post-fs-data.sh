#!/system/bin/sh
# post-fs-data.sh -- intentionally a NO-OP.
#
# The memory tuning is NOT applied here, on purpose.  docs/15 §22.2 measured that lmkd
# rewrites /sys/module/lowmemorykiller/parameters/minfree on every boot, and lmkd starts
# after post-fs-data.  A table written from this stage is therefore overwritten and the
# module would log success while doing nothing.  The real apply lives in service.sh
# (late_start), which runs after lmkd has published its own table.
#
# This file exists only so KernelSU has a well-formed module directory.

LOG=/data/local/tmp/derp_memtune.log
exec >> "$LOG" 2>&1
echo "=== post-fs-data $(date): no-op by design; the apply happens in service.sh (late_start, after lmkd) ==="
exit 0
