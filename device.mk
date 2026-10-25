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

# lmkd thresholds must be re-asserted in the PRODUCT property space.
#
# MEASURED: with the lmkd block only in PRODUCT_PROPERTY_OVERRIDES (which this
# tree routes to vendor/build.prop), the device reported ro.lmk.medium = 700,
# not the 800 set here. Cause: phone-xhdpi-4096-dalvik-heap.mk (inherited
# above, device.mk:16) contributes `ro.lmk.medium?=700` to
# PRODUCT_PRODUCT_PROPERTIES, which lands in /product/etc/build.prop
# (generated: out/target/product/a30s/system/product/etc/build.prop:99).
# Plain ro.* keys are NOT namespaced, and the product property set is loaded
# AFTER vendor's, so 700 overwrote our vendor-side 800.
#
# The same split is why ro.lmk.minfree_levels and ro.lmk.swap_boost_max were
# absent from getprop on device even though both are present in the built
# vendor/build.prop (lines 170 and 175): only /product/etc/build.prop was
# proven to load for this key set on this layout.
#
# Fix: emit the whole lmkd block into PRODUCT_PRODUCT_PROPERTIES as well, from
# a block that comes AFTER the inherit, so each key appears later in the same
# generated file and therefore wins. Kept in vendor/build.prop too so the
# tuning survives either load order.
PRODUCT_PRODUCT_PROPERTIES += \
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

# Target Info
TARGET_DEVICE := a30s
TARGET_SOC := exynos7904

# Bootanimation
TARGET_SCREEN_HEIGHT := 2280
TARGET_SCREEN_WIDTH := 1080

# Fingerprint
PRODUCT_PACKAGES += \
    android.hardware.biometrics.fingerprint-service.samsung

# KernelSU manager, shipped as a system app.
#
# The kernel side is built into this ROM (CONFIG_KSU=y, KSU_VERSION 32473), but
# the manager app was only ever installed by hand into /data, so formatting data
# left the device with a root-capable kernel and no way to grant root. Naming it
# here puts the APK in /system/app and it is present on the first boot after a
# data wipe.
#
# prebuilt/KernelSU.apk is not tracked (prebuilt/*.apk is gitignored, like the
# AGC and Google Photos APKs). Re-fetch it before a clean build:
#
#   curl -L -o prebuilt/KernelSU.apk \
#     https://github.com/rsuntk/KernelSU/releases/download/v3.2.2-10-legacy/\
#     KernelSU_v3.2.2-10-legacy-42-g915b4872_32490-release.apk
#   sha256sum prebuilt/KernelSU.apk   # 78fe80980e65d30ced2a5f560680f8d6343d4443baee4c3bf1c82cbd6847147d
#
# v3.2.2-10-legacy (32490) is the release that reports "Working LEGACY,
# Version: 32473" against this kernel; the package name inside the APK is the
# randomized wffxxf.nclgit.cawxcw, which is what `pm list packages` will show.
PRODUCT_PACKAGES += \
    KernelSU

# KernelSU's native libraries must sit NEXT TO the APK, not inside it.
#
# The release APK ships lib/arm64-v8a/*.so DEFLATED and declares
# android:extractNativeLibs="true". For a pristine system app PackageManager
# never extracts anything: ApplicationInfo.nativeLibraryDir is simply
# /system/app/<name>/lib/<abi>, and with nothing there System.loadLibrary dies:
#
#   E AndroidRuntime: java.lang.UnsatisfiedLinkError:
#       dlopen failed: library "libkernelsu.so" not found
#           at wffxxf.nclgit.cawxcw.Natives.<clinit>
#
# Verified on device 2026-10-24: the manager crashed from /system/app and worked
# only after the same APK was installed as a data-app update.
#
# Uncompressing the entries inside the APK is not an option: the APK is presigned
# and rewriting it invalidates the v2/v3 signature. Installing the libraries
# beside it is what LOCAL_PREBUILT_JNI_LIBS does for make-based prebuilts, and it
# leaves the APK byte-identical.
#
# libksud.so and libmagiskboot.so must keep their executable bit through the
# copy: the manager does not load them, it RUNS them. KsuCli builds its root
# shell from `<nativeLibraryDir>/libksud.so` (ksud's own su server) and hands
# libmagiskboot.so to `ksud install`, which copies it to /data/adb/ksu/bin and
# executes it. With the 0644 that unzip produces, a fresh install dies with
#
#   W KsuCli: Caused by: java.io.IOException:
#       Cannot run program "/system/app/KernelSU/lib/arm64/libksud.so":
#       error=13, Permission denied
#
# and the manager cannot bootstrap /data/adb/ksu at all. PRODUCT_COPY_FILES copies
# with rm -f + cp, so the staged file keeps the source mode - but that is NOT what
# the image gets: mkfs.erofs calls libcutils fs_config(), and the generic
# "system/app/*" rule there forces 0644 on everything below it. The executable bit
# is therefore declared in system/core/libcutils/fs_config.cpp (two explicit 00755
# entries), which is the only lever that reaches the image. Verify on the mounted
# built system.img, never on the staged tree.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilt/kernelsu-libs/arm64/libadbroot.so:$(TARGET_COPY_OUT_SYSTEM)/app/KernelSU/lib/arm64/libadbroot.so \
    $(LOCAL_PATH)/prebuilt/kernelsu-libs/arm64/libkernelsu.so:$(TARGET_COPY_OUT_SYSTEM)/app/KernelSU/lib/arm64/libkernelsu.so \
    $(LOCAL_PATH)/prebuilt/kernelsu-libs/arm64/libksud.so:$(TARGET_COPY_OUT_SYSTEM)/app/KernelSU/lib/arm64/libksud.so \
    $(LOCAL_PATH)/prebuilt/kernelsu-libs/arm64/libmagiskboot.so:$(TARGET_COPY_OUT_SYSTEM)/app/KernelSU/lib/arm64/libmagiskboot.so

# /system/etc/Changelog.txt MUST be a declared output.
#
# vendor/lineage/build/tools/changelog.sh writes it with
#     cp Changelog.txt $OUT_DIR/target/product/$DEVICE/system/etc/
# and the build invokes that script as the FIRST command of the system-image
# rule - i.e. AFTER obj/PACKAGING/system_intermediates/file_list.txt was
# generated from the declared install list. system.img is packed with
#     build_image --input-directory-filter-file .../file_list.txt
# so anything absent from that list is dropped from the image, while the OTA zip
# (packed from the raw staging tree by add_img_to_target_files) still ships it.
# Result before this entry: the zip carried etc/Changelog.txt and the flashed
# image did not - a silent image/zip divergence, which hm_mod/prep_flash.sh
# refuses to stage past.
#
# Declaring the path here puts it in file_list.txt; changelog.sh then overwrites
# the installed placeholder with the real changelog before build_image runs, so
# the packed file is the current one, not the placeholder text.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilt/Changelog.txt:$(TARGET_COPY_OUT_SYSTEM)/etc/Changelog.txt

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

# bpfloader version gate. netbpfload (packages/modules/Connectivity/bpf/loader/
# NetBpfLoad.cpp, reached via bpf/headers/include/bpf/KernelUtils.h
# getKernelVersion) honours ro.bpf.kver_override. On this 4.4 kernel the loader
# otherwise version-gates every map and program out, loads nothing, and never
# sets bpf.progs_loaded - so lmkd/netd log 'BPF-less kernel?' and report empty
# network stats. The kernel already backports what the traffic programs need:
# bpf_obj_pin/bpf_obj_get, cgroup+socket+net_cls BPF, array/hashtable/percpu/
# lpm maps, and (see kernel commit for patch_arsh.py) BPF_ARSH scalar tracking.
# 4.13.0 is the highest honest claim: >=4.14 trips netbpfload's validateProg
# JIT gate (mainline programs get jit:0 on this kernel), 5.4 would demand
# DEVMAP_HASH maps the backport cannot create, and 4.13 selects the 4_9
# program variants ([4_9, 4_19)) that this kernel's verifier now accepts.
# Must be SYSTEM, not VENDOR: a vendor-namespace prop is not readable by the
# loader during early boot (SELinux default_prop labelling) - moving it here
# is what actually delivers the claim.
PRODUCT_SYSTEM_PROPERTIES += ro.bpf.kver_override=4.13.0
# MGLRU (backported in the 4.4 kernel tree): default value for the
# mglru_native DeviceConfig flag. core is the honest target on Exynos 7885
# (ARMv8.0, no hardware AF/DBM): asking for all would read back the same
# 0x0001 in /sys/kernel/mm/lru_gen/enabled. SYSTEM, not VENDOR: init loads
# /system/build.prop under u:r:init:s0, which has the AOSP blanket allow for
# property_type:property_service set (no sepolicy change needed). A value
# persisted in /data/property wins over this default.
PRODUCT_SYSTEM_PROPERTIES += persist.device_config.mglru_native.lru_gen_config=core

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

# Camera HAL3 (merged from Skia_Vulkan_MOD). The SkiaVK renderer override was
# removed 2026-10-18: forcing skiavk broke the Antutu video-edit subtest
# (score 0.0; without the override the renderer defaults to skiagl because
# ro.hwui.use_vulkan is empty). See docs/projects/VIDEO-MODULE.md. The module
# QCOM pile is placebo on Exynos and is skipped, as is spkr_prot disable
# (removes speaker protection).
PRODUCT_PROPERTY_OVERRIDES += \
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

# Derp charger-token-boot handoff.
#
# Installed with PRODUCT_COPY_FILES rather than a sh_binary init_rc: the guard
# script that needed an exec type is gone (u:r:su:s0 does not exist on this
# user build - root here is u:r:ksu:s0), and there is no script left to hang
# init_rc off. The handoff itself is two init builtins and needs no binary.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/derp_charger_token.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/derp_charger_token.rc

# AGC first-boot self-update: AGC is a /system app whose PairIP-protected
# runtime crashes only in the /system install context; pm records the same
# APK as an update to /data/app at first boot and the app runs. Crash
# evidence and the test matrix are in docs/projects/CAMERA_CAPTURE_STALL.md
# (PairIP / system-install section). The .rc starts the script on
# sys.boot_completed=1 in the shell domain.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/agc_boot_update.sh:$(TARGET_COPY_OUT_SYSTEM)/bin/agc_boot_update.sh \
    $(LOCAL_PATH)/agc_boot_update.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/agc_boot_update.rc
