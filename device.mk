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

# A30sUdfpsEnrollGeometryOverlay must be named explicitly.
#
# As an auto-installed Soong module it BUILT and was copied into the staged tree
# (installed-files.txt line 3028: /system/product/overlay/A30sUdfpsEnrollGeometryOverlay.apk)
# but never reached the filesystem image: obj/PACKAGING/system_intermediates/file_list.txt
# - the manifest mkbootfs actually consumes - did not contain it, so every
# systemimage repacked without it (grep of system.img: 0 occurrences, against a
# positive control where GooglePhotosGalleryOverlay is 1). Deleting file_list.txt and
# rebuilding regenerated a byte-identical file, so the manifest is derived from the
# make/PRODUCT view and not from installed-files.txt; only packages reachable from
# PRODUCT_PACKAGES or from a DEVICE_PACKAGE_OVERLAYS root land in it, and
# udfps_settings_overlay/ is neither.
PRODUCT_PACKAGES += A30sUdfpsEnrollGeometryOverlay

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

# Telephony: default the preferred network mode to LTE-preferred (9 =
# RILConstants.NETWORK_MODE_LTE_GSM_WCDMA) for both DSDS slots. Without this the
# framework falls back to NETWORK_MODE_WCDMA_PREF (3G preferred) and a freshly
# formatted /data comes up on 3G. See RILConstants.PREFERRED_NETWORK_MODE.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.telephony.default_network=9,9

# LMK tuning for 2.7GB RAM + zram, now wired to KERNEL PSI (not vmpressure).
#
# The kernel side of PSI is in place: CONFIG_PSI=y in the defconfigs and
# psi=1 on BOARD_KERNEL_CMDLINE. lmkd reads pressure through libpsi, which
# opens /proc/pressure/{io,memory,cpu} O_WRONLY and writes
# "some <threshold_us> <window_us>". Until now every threshold below was
# unset, so lmkd fell back to vmpressure-style defaults and the PSI signal
# changed nothing - kernel PSI was only half the feature.
#
# Sized for THIS device (2.7 GB / 3860 mAh), not copied from a 4 GB reference:
#   * minfree_levels follow the AOSP ladder whose top tier (80640 pages =
#     315 MB) suits 2.7 GB. Units are pages:score.
#   * upgrade_pressure=60 lets lmkd escalate to the medium PSI level while
#     ~40% of the window is still clean; downgrade_pressure=100 so it backs
#     off only once pressure fully clears. Aggressive escalation is correct
#     on 2.7 GB with zram writeback: stalls are expensive here.
#   * ro.lmk.critical=0 with critical_upgrade=false - no separate critical
#     kill tier; the medium PSI level plus kill_heaviest_task does the work.
#     Avoids double-killing on a device with little headroom.
#   * swap_util_max=90 stops swapping into zram at 90% use so the backing
#     partition (once the repartition lands) keeps headroom.
#   * ro.lmk.debug stays TRUE deliberately: it was enabled for the OOM
#     forensics round and is the evidence channel for Phase 1 bug #4
#     (BatteryStats per-app mAh = 0). Do not disable it before that is
#     closed.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.lmk.use_psi=true \
    ro.lmk.low=1001 \
    ro.lmk.medium=800 \
    ro.lmk.critical=0 \
    ro.lmk.critical_upgrade=false \
    ro.lmk.upgrade_pressure=60 \
    ro.lmk.downgrade_pressure=100 \
    ro.lmk.kill_heaviest_task=true \
    ro.lmk.kill_timeout_ms=100 \
    ro.lmk.use_minfree_levels=true \
    ro.lmk.minfree_levels=18432:0,23040:100,27648:200,32256:250,55296:850,80640:950 \
    ro.lmk.swap_util_max=90 \
    ro.lmk.swap_free_low_percentage=10 \
    ro.lmk.thrashing_limit=30 \
    ro.lmk.thrashing_limit_decay=10 \
    ro.lmk.swap_boost_max=100 \
    ro.lmk.debug=true

# ART dex2oat threading: AOSP's guidance is that the thread count should equal
# the number of CPUs in the CPU set. This SoC has 8 CPUs, all present and
# online (/sys/devices/system/cpu/{online,possible,present} are all "0-7").
#
# CPU-SET FORMAT IS NOT A RANGE. odrefresh's IsCpuSetSpecValid()
# (art/odrefresh/odrefresh.cc:442) splits on ',' and ParseInt()s each token, so
# a range like "0-7" fails validation and odrefresh aborts the entire
# compilation with "Invalid CPU set spec". It must be an explicit list.
#
# Commas in a value are safe here: PRODUCT_PROPERTY_OVERRIDES emits each
# whitespace-separated token verbatim (proof in the generated build.prop:
# ro.system.product.cpu.abilist=arm64-v8a,armeabi-v7a,armeabi).
#
# All eight dalvik.vm.*dex2oat-* properties are in kIgnoredSystemProperties
# (art/odrefresh/odr_config.h:50), so changing them does NOT invalidate
# already-compiled artifacts.
#
# Only the base and background pairs are set. In
# AddDex2OatConcurrencyArguments() (odrefresh.cc:454) the background pair falls
# back to the base pair, but dalvik.vm.boot-dex2oat-* and
# dalvik.vm.restore-dex2oat-* have NO fallback, so they are left at the dex2oat
# defaults deliberately rather than changing post-OTA boot behaviour blind.
PRODUCT_PROPERTY_OVERRIDES += \
    dalvik.vm.dex2oat-threads=8 \
    dalvik.vm.dex2oat-cpu-set=0,1,2,3,4,5,6,7 \
    dalvik.vm.background-dex2oat-threads=8 \
    dalvik.vm.background-dex2oat-cpu-set=0,1,2,3,4,5,6,7


# Service definition; starts on sys.boot_completed=1, see the file for why.
PRODUCT_COPY_FILES += \
