DEVICE_PATH := device/samsung/a30s

# Fingerprint
$(call soong_config_set,surfaceflinger,udfps_lib,//hardware/samsung/fingerprint:libudfps_extension.samsung)
$(call soong_config_set,samsungUdfpsVars,dim_layer_zorder,0x20000001u)
BOARD_UDFPS_DIM_LAYER_ZORDER := 0x20000001u

# Inherit common board flags
include device/samsung/exynos7885-common/BoardConfigCommon.mk

# Asserts
TARGET_OTA_ASSERT_DEVICE := a30s,a30sdd

# Display
TARGET_SCREEN_DENSITY := 280

# Kernel
# Kernel cmdline — REQUIRED: first_stage init locates fstab.${hardware} and
# init.${hardware}.rc via androidboot.hardware. Known-good TWRP/OrangeFox and stock
# images all carry this; our mkbootimg images had an empty cmdline field (bootloop).
BOARD_KERNEL_CMDLINE := androidboot.hardware=exynos7904 psi=1
BOARD_MKBOOTIMG_ARGS += --cmdline "$(BOARD_KERNEL_CMDLINE)"

TARGET_KERNEL_CONFIG := full/exynos7885-a30s_defconfig
# Use prebuilt clang for host tools (Debian gcc-14 errors on implicit decls in 4.4 vendor scripts)
# a30s: Neutron Clang 24 builds the kernel (proven trial-3); host tools stay on stock r563880c (Neutron segfaults host binaries vs glibc-2.17 sysroot)
# Portable: native Arch exports TARGET_KERNEL_CLANG_PATH=/mnt/aosp/toolchains/neutron-clang-24
# from hm_mod/lib/derp_env.sh; without it this falls back to $(HOME)/toolchains (the WSL layout).
TARGET_KERNEL_CLANG_PATH ?= $(HOME)/toolchains
TARGET_KERNEL_ADDITIONAL_FLAGS := HOSTCC=$(shell pwd)/prebuilts/clang/host/linux-x86/clang-r563880c/bin/clang HOSTCXX=$(shell pwd)/prebuilts/clang/host/linux-x86/clang-r563880c/bin/clang++ CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu- STRIP=$(shell pwd)/prebuilts/clang/host/linux-x86/clang-r563880c/bin/llvm-strip

# Partitions
#
# Geometry is the LIVE one, re-measured 2026-10-09 from both the recovery and
# the booted kernel and recorded in docs/40-DEVICE-INVARIANTS.md:
#   p25 system = 2,600,468,480 B (2480 MiB)
#   p26 vendor =   268,435,456 B ( 256 MiB)
# These MUST match, because PARTITION_SIZE is the hard cap on the image and the
# block OTA writes every block the transfer list names.
#
# The tree was re-imported on 2026-10-22 with 4194304000/645922816 (an ODIN
# restore had already reset the partitions back to the stock sizes). Those
# values cannot flash: the ext4 images they produce are 3.0 GiB/277 MiB, i.e.
# larger than the partitions.
#
# FIX: build system and vendor as EROFS (as this tree did before the re-import,
# commit "BoardConfigCommon: build system and vendor images as erofs",
# 2026-10-08). EROFS output is content-sized and compressed:
#   Oct-13 image: system 2,074,411,008 B (506,448 blocks), vendor 155,131,904 B
# Both fit the live geometry with room to spare. The 4.4 kernel has
# CONFIG_EROFS_FS(_ZIP)=y and supports the LZ4 0padding format that the default
# BOARD_EROFS_COMPRESSOR (lz4hc,9) emits; fstab.exynos7904 already carries both
# the ext4 and erofs lines.
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 55574528
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 2600468480
BOARD_CACHEIMAGE_PARTITION_SIZE := 209715200
BOARD_VENDORIMAGE_PARTITION_SIZE   := 268435456

# Properties
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop

# SPL
VENDOR_SECURITY_PATCH := 2021-11-01

# Touch HAL: a30s firmware supports glove_mode AND hover_enable (stylus),
# so the HAL registers IGloveMode + IStylusMode; declare both (the common
# else-branch manifest only declares IGloveMode, which makes A16
# servicemanager reject the IStylusMode registration and crash-loops the HAL).
# Replace the common else-branch manifest_touch.xml (IGloveMode-only) with the
# a30s-specific one (IGloveMode + IStylusMode + ITouchscreenGesture) - the firmware
# cmd_list supports all three and A16 servicemanager rejects undeclared interfaces.
DEVICE_MANIFEST_FILE := $(filter-out $(COMMON_PATH)/manifest_touch.xml,$(DEVICE_MANIFEST_FILE))
DEVICE_MANIFEST_FILE += $(DEVICE_PATH)/manifest_touch_a30s.xml
