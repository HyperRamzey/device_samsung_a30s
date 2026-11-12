# Testing/diagnostic variant of lineage_a30s. NOT FOR RELEASE.
#
# This file is the only place in the a30s / exynos7885-common stack that turns on
# unauthenticated ADB and root adbd, and it gates the early ADB gadget trigger. The
# release product (lineage_a30s.mk) leaves DERP_TESTING unset, so those things are
# absent from its build.prop and its image: the difference is structural, not a step
# someone has to remember before publishing.
#
# Why a separate product instead of an env var on the same product: an env switch can
# be unset by the next shell, a CI job, or a re-invocation through a different
# wrapper, and the artifact that comes out the other side has the same name -- the
# only clue is inside build.prop. A product name puts the difference in the lunch
# target, the out path, and the zip filename, so a testing image cannot be handed to
# somebody as a release by accident. Which artifact you ran is readable from the
# device too, without a serial: PRODUCT_NAME lands in ro.product.name, so
# `adb shell getprop ro.product.name` answers `lineage_a30s_testing` or
# `lineage_a30s`. No custom marker property is declared, because a new ro.* prefix
# needs property_contexts work and the free one already says it.
#
# The three switches, what each costs, and where each one is read:
#
#   WITH_ADB_INSECURE        -> ro.adb.secure=0. adbd stops challenging the host, so
#                         a hung system_server or a pre-unlock boot is still reachable
#                         over USB. Set in lineage_a30s.mk under this flag; read by
#                         adbd's own auth path. Any host with a cable gets a shell.
#   DERP_TESTING            also gates zzz-early-adb.rc in device/samsung/
#                         exynos7885-common/exynos7885-common.mk, which brings the
#                         gadget up from init at `on boot` instead of waiting for
#                         UsbService late in boot. That file's own comments explain
#                         why the key-store repair has to precede the setprop.
#   service.adb.root=1      adbd runs as uid 0 from the moment it starts.
#
# service.adb.root is a property and NOT an init trigger, on purpose, and it is
# deliberately not in an .rc file. Two measured reasons:
#   - adbd only roots when the property literally equals "1"; there is no
#     default-to-root for userdebug. See packages/modules/adb/daemon/main.cpp:66-92
#     (should_drop_privileges(): ro.secure drops privileges, then
#     `if (ro_debuggable && adb_root) drop = false`). ro.adb.secure=0 alone buys
#     no authentication, NOT root: that is a shell user.
#   - an `on early-boot` / `setprop service.adb.root 1` in an rc would be denied:
#     service.adb.root is labeled shell_prop (system/sepolicy/private/
#     property_contexts:52) and init has no grant on it -- zero shell_prop lines in
#     system/sepolicy/private/init.te; the only setters are adbd (private/adbd.te:81)
#     and shell (private/shell.te:170). It would read like a guarantee and deliver
#     nothing, which is the failure mode zzz-early-adb.rc documents at length.
# A build.prop property is set by init while loading the image's props, so it is in
# place before adbd is ever started -- strictly earlier than any trigger could be.
#
# VERIFY ON DEVICE after flashing a testing build; do not trust this file:
#   adb shell getprop service.adb.root     -> 1
#   adb shell id                           -> uid=0
#   adb shell getprop ro.product.name      -> lineage_a30s_testing
# If `id` says uid=2000 the property did not reach the image; the build-time check in
# hm_mod/build_dual.sh reads the prop back out of the zip for exactly that reason.
#
# Read this before deciding a testing build is "just for me": ro.debuggable=1 plus a
# root shell on USB with no prompt is a full unlock for anyone who plugs the phone
# into anything. Never link one for other people to download. Note also that
# ro.build.type says userdebug while the inherited fingerprint still claims
# user/release-keys (kept for partition/OTA stock parity, docs/40-DEVICE-INVARIANTS.md),
# so fingerprint alone does not identify a testing artifact either.
#
# Related documentation: docs/02-ROM-BUILD.md, docs/03-FLASH-AND-GATE.md,
# docs/04-RELEASE-AND-OTA.md

# Must precede the inherit: the flag is read by lineage_a30s.mk and by
# exynos7885-common.mk while this product config is being evaluated.
DERP_TESTING := 1

$(call inherit-product, device/samsung/a30s/lineage_a30s.mk)

PRODUCT_NAME := lineage_a30s_testing

PRODUCT_PRODUCT_PROPERTIES += \
    service.adb.root=1
