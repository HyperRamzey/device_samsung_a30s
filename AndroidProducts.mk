# Copyright (C) 2025 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

# lineage_a30s_testing is the authenticated early-root diagnostic variant: it
# sets DERP_TESTING=1, keeps ro.adb.secure=1, keeps ro.debuggable=1, and adds
# service.adb.root=1. See lineage_a30s_testing.mk for full details and key-injection steps.
PRODUCT_MAKEFILES += \
    $(LOCAL_DIR)/lineage_a30s.mk \
    $(LOCAL_DIR)/lineage_a30s_testing.mk
