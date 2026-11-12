# Copyright (C) 2025 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/product_launched_with_p.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/non_ab_device.mk)

# Bring-up: keep adb usable for diagnosis -- on the TESTING build only.
#
# This was unconditional, which meant every public release carried ro.adb.secure=0
# and a debuggable userdebug: any host with a cable got an unauthenticated shell on
# a stranger's phone, with no prompt and no key. The same reasoning that removed
# PRODUCT_ADB_KEYS for the public release (GitHub issue #2, note further down this
# file) applies here, and was simply never applied to this line.
#
# Lineage's common.mk sets ro.adb.secure=1 + PRODUCT_NOT_DEBUGGABLE_IN_USERDEBUG :=
# true when WITH_ADB_INSECURE is unset (evaluated at inherit time), which yields
# ro.debuggable=0 even in userdebug builds and authenticated adb. That is now the
# release behaviour. DERP_TESTING is set by lineage_a30s_testing.mk before it
# inherits this file, and that product also carries service.adb.root=1; see
# device/samsung/a30s/lineage_a30s_testing.mk for what each property buys and for
# the adbd/sepolicy citations behind it.
#
# Still set BEFORE the lineage inherit, because that is when common.mk reads it.
ifeq ($(DERP_TESTING),1)
WITH_ADB_INSECURE := true
endif

# Inherit LineageOS common device config
PRODUCT_NO_CAMERA := true

$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Inherit device configuration
$(call inherit-product, device/samsung/a30s/device.mk)

# Device identifier. This must come after all inclusions
PRODUCT_DEVICE := a30s
PRODUCT_NAME := lineage_a30s
PRODUCT_MODEL := SM-A307F
PRODUCT_BRAND := samsung
PRODUCT_MANUFACTURER := samsung

# PRODUCT_ADB_KEYS must stay unset on release builds: it ships the
# build host's public key as /product/etc/security/adb_keys (symlinked to
# /adb_keys), which authorizes that host for adb shell on every device
# running this build with no RSA confirmation prompt. Removed for the
# public release (GitHub issue #2); adbd loads user keys from
# /data/misc/adb/adb_keys instead.

PRODUCT_GMS_CLIENTID_BASE := android-samsung

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="a30sxx-user 11 RP1A.200720.012 A307FNXXU4CWH7 release-keys" \
    BuildFingerprint=samsung/a30sxx/a30s:11/RP1A.200720.012/A307FNXXU4CWH7:user/release-keys
PRODUCT_PACKAGES += AGC GooglePhotosGalleryOverlay

# Stock Gallery is not shipped on this device: Google Photos is the photos/gallery
# app (installed at first boot by derp-gphotos-install.rc, see device.mk and
# docs/projects/PHOTOS-APP.md). The removal that actually took effect is the deleted
# Gallery2 line in vendor/lineage/config/common_mobile.mk. This filter is a
# belt-and-braces net for the same name coming back through another inherit;
# measured on its own it removed nothing (Gallery2.apk stayed in
# out/soong/installs-lineage_a30s.mk and in the system image), which is why the
# upstream config edit is the primary fix. Re-check both after a `repo sync`:
# docs/45-FORK-UPSTREAM-MERGES.md.
PRODUCT_PACKAGES := $(filter-out Gallery2,$(PRODUCT_PACKAGES))

