# Copyright (C) 2025 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/product_launched_with_p.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/non_ab_device.mk)

# Bring-up: keep adb usable for diagnosis. Lineage's common.mk sets
# ro.adb.secure=1 + PRODUCT_NOT_DEBUGGABLE_IN_USERDEBUG := true when
# WITH_ADB_INSECURE is unset (evaluated at inherit time), which yields
# ro.debuggable=0 even in userdebug builds and authenticated adb (impossible
# to accept headless while the boot hangs). Set BEFORE the lineage inherit.
WITH_ADB_INSECURE := true

# Inherit LineageOS common device config
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Inherit device configuration
$(call inherit-product, device/samsung/a30s/device.mk)

# Device identifier. This must come after all inclusions
PRODUCT_DEVICE := a30s
PRODUCT_NAME := lineage_a30s
PRODUCT_MODEL := SM-A307F
PRODUCT_BRAND := samsung
PRODUCT_MANUFACTURER := samsung

# Bring-up: ship the build host's adb public key as a product adb_keys file
# (/product/etc/security/adb_keys, world-readable). adbd's IteratePublicKeys
# fallback reads /adb_keys (symlink to this) when the framework auth broker is
# unavailable (system_server hung/crashed during bring-up), authorizing this
# host without the RSA confirmation dialog.
PRODUCT_ADB_KEYS := device/samsung/exynos7885-common/adb/adb_keys

PRODUCT_GMS_CLIENTID_BASE := android-samsung

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="a30sxx-user 11 RP1A.200720.012 A307FNXXU4CWH7 release-keys" \
    BuildFingerprint=samsung/a30sxx/a30s:11/RP1A.200720.012/A307FNXXU4CWH7:user/release-keys
