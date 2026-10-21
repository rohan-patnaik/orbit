#pragma once
#include <cstdint>

namespace Orbit {
// EWMH direction 8 is pointer move; Chromium uses button 0, Qt uses 1.
// Coordinates in the message are not authoritative on scaled monitors.
struct XwaylandMoveContext {
    bool leftHeld, inputHeld, locked, mapped, visible, focused;
    bool ordinaryWorkspace, pointerInside, dragActive;
};
constexpr bool acceptsXwaylandMove(uint8_t format, uint32_t direction, uint32_t button,
                                   const XwaylandMoveContext& c) {
    return format == 32 && direction == 8 && (button == 0 || button == 1)
        && c.leftHeld && c.inputHeld && !c.locked && c.mapped && c.visible
        && c.focused && c.ordinaryWorkspace && c.pointerInside && !c.dragActive;
}
} // namespace Orbit
