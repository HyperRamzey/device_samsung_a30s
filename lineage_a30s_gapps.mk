# GApps variant of lineage_a30s (MindTheGapps inline integration)

$(call inherit-product, device/samsung/a30s/lineage_a30s.mk)

PRODUCT_NAME := lineage_a30s_gapps

# Inherit MindTheGapps arm64 vendor definitions
$(call inherit-product-if-exists, vendor/gapps/arm64/arm64-vendor.mk)

# OTA: this product updates from a30s_gapps.json and nothing else. The feed URL is a
# single string resource in packages/apps/Updater, and the app has no GApps channel
# (UpdateChannel is RELEASE | TESTING), so the only place it can be set per variant is
# an overlay the product adds itself. Without this line a GApps device polls the clean
# feed and an "OTA" would strip GmsCore/Phonesky off a working system.
DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay-lineage-gapps
