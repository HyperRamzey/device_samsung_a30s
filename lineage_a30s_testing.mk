# Testing/diagnostic variant of lineage_a30s (authenticated early root adb).
#
# Both release (lineage_a30s) and testing (lineage_a30s_testing) enforce
# ro.adb.secure=1 by leaving WITH_ADB_INSECURE unset everywhere (GitHub issue #10):
# any unapproved USB host is rejected, even over early gadget bring-up.
#
# Why a separate product instead of an env var on the same product: an env switch can
# be unset by the next shell, a CI job, or a re-invocation through a different
# wrapper, and the artifact that comes out the other side has the same name -- the
# only clue is inside build.prop. A product name puts the difference in the lunch
# target, the out path, and the zip filename. Which artifact you ran is readable from
# the device too: PRODUCT_NAME lands in ro.product.name (`lineage_a30s_testing` vs
# `lineage_a30s`).
#
# The three switches that distinguish testing from release:
#
#   DERP_TESTING=1          gates zzz-early-adb.rc in device/samsung/
#                           exynos7885-common/exynos7885-common.mk, bringing up the
#                           USB adb gadget from init at `on boot` (and repairing
#                           /data/misc/adb permissions first) instead of waiting for
#                           UsbService late in boot.
#   PRODUCT_NOT_DEBUGGABLE_IN_USERDEBUG :=
#                           MUST be cleared empty AFTER inheriting lineage_a30s.mk.
#                           vendor/lineage/config/common.mk sets it to `true` when
#                           WITH_ADB_INSECURE is unset, and build/make/common/json.mk's
#                           add_json_bool treats ANY non-empty string (even `false`)
#                           as true, which would make gen_build_prop.py emit
#                           ro.debuggable=0 and prevent adbd from keeping root.
#   service.adb.root=1      adbd runs as uid 0 once an authorized host connects.
#
# adbd checks `if (ro_debuggable && adb_root) drop = false` (packages/modules/adb/
# daemon/main.cpp:66-92), and service.adb.root is labelled shell_prop
# (system/sepolicy/private/property_contexts:52) which init cannot set from an .rc
# trigger, so it must stay in build.prop.
#
# VERIFY ON DEVICE after flashing a testing build + injecting host pubkey in OFOX:
#   unauthorized host: `adb devices`       -> unauthorized (ro.adb.secure=1)
#   authorized host:
#     adb shell getprop ro.adb.secure      -> 1
#     adb shell getprop ro.debuggable      -> 1
#     adb shell getprop service.adb.root   -> 1
#     adb shell getprop ro.product.name    -> lineage_a30s_testing
#     adb shell id                         -> uid=0(root)
#
# Note also that ro.build.type says userdebug while the inherited fingerprint still
# claims user/release-keys (kept for partition/OTA stock parity,
# docs/40-DEVICE-INVARIANTS.md).
#
# Related documentation: docs/02-ROM-BUILD.md, docs/03-FLASH-AND-GATE.md,
# docs/04-RELEASE-AND-OTA.md, docs/06-TESTING-AND-SECURE-BUILDS.md

# Must precede the inherit: DERP_TESTING is read by exynos7885-common.mk while this
# product config is being evaluated.
DERP_TESTING := 1

$(call inherit-product, device/samsung/a30s/lineage_a30s.mk)

# Undo vendor/lineage/config/common.mk's default userdebug lockdown so
# ro.debuggable=1 stays enabled for authorized testers' `adb root` while
# ro.adb.secure=1 still enforces host key authentication.
PRODUCT_NOT_DEBUGGABLE_IN_USERDEBUG :=

PRODUCT_NAME := lineage_a30s_testing

PRODUCT_PRODUCT_PROPERTIES += \
    service.adb.root=1
