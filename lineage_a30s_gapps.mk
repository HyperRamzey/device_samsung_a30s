# GApps variant of lineage_a30s (MindTheGapps inline integration)

$(call inherit-product, device/samsung/a30s/lineage_a30s.mk)

PRODUCT_NAME := lineage_a30s_gapps

# Inherit MindTheGapps arm64 vendor definitions
$(call inherit-product-if-exists, vendor/gapps/arm64/arm64-vendor.mk)
