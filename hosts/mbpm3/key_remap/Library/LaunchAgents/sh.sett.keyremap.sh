#!/bin/bash
# Apply Caps Lock → Control remapping and clear macOS per-device overrides.
# Must be run via launchd (has access to hidutil entitlements).

MAPPING='{"UserKeyMapping":[
  {
    "HIDKeyboardModifierMappingSrc": 0x700000039,
    "HIDKeyboardModifierMappingDst": 0x7000000E0
  },
  {
    "HIDKeyboardModifierMappingSrc":0x700000064,
    "HIDKeyboardModifierMappingDst":0x700000035
  }
]}'

# 1. Set global mapping (applies to all keyboards by default)
/usr/bin/hidutil property --set "$MAPPING"

# 2. Clear per-device HIDKeyboardModifierMappingPairs that macOS preferences
#    injects (e.g., identity mappings that override the global UserKeyMapping).
#    This targets all keyboard-like devices.
/usr/bin/hidutil property --matching keyboard --set '{"HIDKeyboardModifierMappingPairs":[]}' 2>/dev/null

# 3. Also set UserKeyMapping explicitly on keyboard devices as a fallback.
/usr/bin/hidutil property --matching keyboard --set "$MAPPING" 2>/dev/null
