# A16 first_stage GetFstabPath: Samsung SAR boot expects the fstab at
# /system/etc/fstab.exynos7904 (androidboot.hardware=exynos7904).
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/fstab.exynos7904:$(TARGET_COPY_OUT_SYSTEM)/etc/fstab.exynos7904

# Copyright (C) 2025 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

# Inherit common device configuration
$(call inherit-product, device/samsung/exynos7885-common/exynos7885-common.mk)

# Inherit proprietary files setup
$(call inherit-product, vendor/samsung/a30s/a30s-vendor.mk)

# Inherit dalvik config
$(call inherit-product, frameworks/native/build/phone-xhdpi-4096-dalvik-heap.mk)

# Target Info
TARGET_DEVICE := a30s
TARGET_SOC := exynos7904

# Bootanimation
TARGET_SCREEN_HEIGHT := 2280
TARGET_SCREEN_WIDTH := 1080

# Fingerprint
PRODUCT_PACKAGES += \
    android.hardware.biometrics.fingerprint-service.samsung

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.fingerprint.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.fingerprint.xml

# Overlay
DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay
DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay-lineage

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += $(LOCAL_PATH)


# Charger-mode: power-key hold in charger mode must continue full boot
# (sys.boot_from_charger_mode=1) instead of reboot(RB_AUTOBOOT), which
# loops forever when the bootloader re-enters charger mode (a30s PMIC
# PWRON latch after freezes). init.rc handles the property.
PRODUCT_VENDOR_PROPERTIES += ro.enable_boot_charger_mode=true
