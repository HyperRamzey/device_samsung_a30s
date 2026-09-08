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
TARGET_KERNEL_CONFIG := full/exynos7885-a30s_defconfig
# Use prebuilt clang for host tools (Debian gcc-14 errors on implicit decls in 4.4 vendor scripts)
TARGET_KERNEL_ADDITIONAL_FLAGS := HOSTCC=clang HOSTCXX=clang++

# Partitions
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 55574528
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 5033164800
BOARD_CACHEIMAGE_PARTITION_SIZE := 209715200
BOARD_VENDORIMAGE_PARTITION_SIZE   := 645922816

# Properties
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop

# SPL
VENDOR_SECURITY_PATCH := 2021-11-01
