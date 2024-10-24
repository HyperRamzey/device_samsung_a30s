# Copyright (C) 2025 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/product_launched_with_p.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/non_ab_device.mk)

# Inherit device configuration
$(call inherit-product, device/samsung/a30s/device.mk)

# Inherit LineageOS common device config
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

BUILD_FINGERPRINT := "samsung/a30sub/a30s:11/RP1A.200720.012/A307GUBS4CUJ1:user/release-keys"

PRODUCT_BUILD_PROP_OVERRIDES += \
   BuildDesc=$(call normalize-path-list, "a30sub-user 11 RP1A.200720.012 A307GUBS4CUJ1 release-keys")

# Device identifier. This must come after all inclusions
PRODUCT_DEVICE := a30s
PRODUCT_NAME := lineage_a30s
PRODUCT_MODEL := SM-A307F
PRODUCT_BRAND := samsung
PRODUCT_MANUFACTURER := samsung
