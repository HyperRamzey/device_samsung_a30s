# Copyright (C) 2025 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

# lineage_a30s_testing is the diagnostic variant: unauthenticated + root adb, and
# it is the only product that sets DERP_TESTING. Never release it. See
# lineage_a30s_testing.mk for the properties, the citations, and the device-side
# verification steps.
PRODUCT_MAKEFILES += \
    $(LOCAL_DIR)/lineage_a30s.mk \
    $(LOCAL_DIR)/lineage_a30s_testing.mk
