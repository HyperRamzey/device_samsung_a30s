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

# bpfloader version gate. bpfloader.rs:428 honours ro.bpf.kver_override (added
# by commit 6c5f4f8, 'bpfloader: Allow overriding kernel version'). On this 4.4
# kernel the loader otherwise version-gates every map and program out, loads
# nothing, and never sets bpf.progs_loaded - so lmkd/netd log 'BPF-less kernel?'
# and report empty network stats. The kernel already backports what the traffic
# programs need: bpf_obj_pin/bpf_obj_get, cgroup+socket+net_cls BPF, and
# array/hashtable/percpu/lpm maps (bpftool feature probe: 'bpf() syscall for
# unprivileged users is enabled'). 5.4.0 is the highest honest claim - the
# backport has no ringbuf (5.8), local_storage (5.7) or queue_stack_maps (5.9),
# so claiming 5.10 would make bpfloader request maps bpf() cannot create.
PRODUCT_VENDOR_PROPERTIES += ro.bpf.kver_override=5.4.0

# Samsung SEH radio manager: binds vendor.samsung.hardware.radio ISehRadio
# (HIDL 2.x) + sends FW_READY. Without it Samsung rild exits (clean) every
# ~30s ("Request processing is disabled" -> silent-reset cycle), re-booting
# the CP via cbd each time and blipping telephony/STK.
PRODUCT_PACKAGES += sehradiomanager

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

# LMK tuning for 2.8GB RAM + zram (OOM forensics 2026-09-18, Morphe SIGKILL):
# kill heaviest cached task first (fewer kills per MB freed), low-RAM swap
# floor, lmkd debug for the next forensics round (userdebug only).
PRODUCT_PROPERTY_OVERRIDES += \
    ro.lmk.kill_heaviest_task=true \
    ro.lmk.swap_free_low_percentage=10 \
    ro.lmk.debug=true
