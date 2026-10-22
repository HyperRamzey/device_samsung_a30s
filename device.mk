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

# Samsung SEH radio manager: binds vendor.samsung.hardware.radio ISehRadio
# (HIDL 2.x) + sends FW_READY. Without it Samsung rild exits (clean) every
# ~30s ("Request processing is disabled" -> silent-reset cycle), re-booting
# the CP via cbd each time and blipping telephony/STK.
PRODUCT_PACKAGES += sehradiomanager

# Fold5 Dolby DAP stack (in-tree, toggle via persist.sys.dolby_f5).
# Blobs ship on /system/dolby_f5 (flashed); init bind-mounts/overlays them
# over /vendor paths when enabled. No vendor.img changes, no module.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/dolby_f5/blobs/lib/soundfx/libswdap.so:$(TARGET_COPY_OUT_SYSTEM)/dolby_f5/lib/soundfx/libswdap.so \
    $(LOCAL_PATH)/dolby_f5/blobs/lib/libprofileparamstorage.so:$(TARGET_COPY_OUT_SYSTEM)/dolby_f5/lib/libprofileparamstorage.so \
    $(LOCAL_PATH)/dolby_f5/blobs/lib/libspatializerparamstorage.so:$(TARGET_COPY_OUT_SYSTEM)/dolby_f5/lib/libspatializerparamstorage.so \
    $(LOCAL_PATH)/dolby_f5/blobs/lib/libsecaudiocoreutils.so:$(TARGET_COPY_OUT_SYSTEM)/dolby_f5/lib/libsecaudiocoreutils.so \
    $(LOCAL_PATH)/dolby_f5/blobs/etc/dolby/dax-default.xml:$(TARGET_COPY_OUT_SYSTEM)/dolby_f5/etc/dolby/dax-default.xml \
    $(LOCAL_PATH)/dolby_f5/blobs/firmware/dax_param.bin:$(TARGET_COPY_OUT_SYSTEM)/dolby_f5/firmware/dax_param.bin \
    $(LOCAL_PATH)/dolby_f5/dolby_f5.sh:$(TARGET_COPY_OUT_SYSTEM)/bin/dolby_f5.sh \
    $(LOCAL_PATH)/dolby_f5/init.dolby_f5.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/dolby_f5.rc

# Dual-mono earpiece helper (in-tree): stock mixer_paths.xml + EP enable at
# unity in media-speaker. Replaces the vendor blob copy (removed from
# proprietary-files.txt / a30s-vendor.mk) so the tree is the single source.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/audio/mixer_paths.xml:$(TARGET_COPY_OUT_VENDOR)/etc/mixer_paths.xml

# SkiaVK renderer + Camera HAL3 (merged from Skia_Vulkan_MOD). The module QCOM pile is placebo on Exynos and is skipped, as is spkr_prot disable (removes speaker protection).
PRODUCT_PROPERTY_OVERRIDES += \
    debug.hwui.renderer=skiavk \
    persist.camera.HAL3.enabled=1 \
    persist.vendor.camera.HAL3.enabled=1

# --- Derp memory tuning, in-tree (docs/15-MEMORY-MANAGEMENT.md sections 22-26) ---
# In-tree so it survives a factory reset and needs no KernelSU module. The module
# copy (hm_mod/ksu_modules/memtune/) is kept only for the adb-only path; this is
# the source of truth.
#
# WHY a property and not a sysctl write: lmkd REWRITES the minfree kernel parameter
# from its properties on every boot (measured, docs/15 22.2), so writing
# /sys/module/lowmemorykiller/parameters/minfree from post-fs-data is overwritten.
# Verified live on RF8M834JT4D: `strings /system/bin/lmkd` contains the literal
# "sys.lmk.minfree_levels", and setting it then restarting lmkd DOES change the
# kernel parameter (18432,...  <-  12288,...). So the property is the correct lever.
#
# The tuned table (docs/15 22.1): adj-0 tier DOWN 72->48 MB so the camera and the
# camera provider leave the kill set except as a last resort; cached tiers UP
# 216/315 -> 240/320 MB so cached apps die earlier in the climb. Measured effect
# (docs/15 22.3): the camera process survives the whole window instead of dying at
# +12-16 s, and MemFree floor rises from 46-67 MB to 68-80 MB.
#   adj array is unchanged (0,100,200,250,900,950) - only the kB values move.
PRODUCT_SYSTEM_PROPERTIES += \
    sys.lmk.minfree_levels=12288:0,16384:100,20480:200,24576:250,61440:900,81920:950

# The sysctl half of the same set. These are NOT rewritten by anything at boot, so
# `on init` in the vendor rc is the right stage (the rc is in publish_common,
# next to the existing ZRAM block). Values and the reason each is measured, not
# guessed:
#   extra_free_kbytes 13162 -> 24576   kswapd band so kswapd runs ahead of the
#                                    allocator instead of the allocator hitting
#                                    direct reclaim (docs/15 22.3)
#   vfs_cache_pressure   50 -> 150     dentry/inode cache was being kept ahead of
#                                    anon, the wrong bias under camera pressure
#   page-cluster          0 -> 3       enable swap readahead. NOTE: on this 4.4
#                                    tree CONFIG_SWAP_ENABLE_READAHEAD is not
#                                    compiled, so this is INERT today (docs/15
#                                    21.1). Written for correctness and labelled
#                                    inert, not claimed as a win.
#   min_free_kbytes             LEFT AT STOCK 32768. docs/15 25.3 shows 131072
#                                    would exceed the adj-0 tier (inverted
#                                    ordering) and cost more than the ion
#                                    headroom, so the vendor value stands.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/memtune/init.memtune.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.memtune.rc

