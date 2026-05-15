// Compatibility shim for xkbcommon < 1.11.0 (Debian trixie ships 1.7.0)
// Hyprland uses XKB_KEYMAP_FORMAT_TEXT_V2 and xkb_keymap_new_from_names2
// which were added in xkbcommon 1.11.0.
#pragma once
#include <xkbcommon/xkbcommon.h>

#if XKBCOMMON_COMPAT
#define XKB_KEYMAP_FORMAT_TEXT_V2 XKB_KEYMAP_FORMAT_TEXT_V1

// xkb_keymap_new_from_names2 was added in 1.11.0. For older versions,
// wrap xkb_keymap_new_from_names (which takes ctx, names, flags).
inline xkb_keymap* xkb_keymap_new_from_names2(struct xkb_context* ctx,
                                               const struct xkb_rule_names* names,
                                               enum xkb_keymap_format format,
                                               enum xkb_keymap_compile_flags flags) {
    (void)format;
    return xkb_keymap_new_from_names(ctx, names, flags);
}
#endif
