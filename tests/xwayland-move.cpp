#include "../native/XwaylandMove.hpp"
#include <cassert>
#include <initializer_list>
int main() {
    Orbit::XwaylandMoveContext valid{true, true, false, true, true, true, true, true, false};
    auto accepts = [](const auto& c, unsigned format=32, unsigned direction=8, unsigned button=0) {
        return Orbit::acceptsXwaylandMove(format, direction, button, c);
    };
    assert(accepts(valid)); // Chromium
    assert(accepts(valid, 32, 8, 1)); // Qt
    for (unsigned format : {0u, 8u, 16u}) assert(!accepts(valid, format));
    for (unsigned direction=0; direction<=12; ++direction)
        if (direction != 8) assert(!accepts(valid, 32, direction));
    for (unsigned button : {2u, 3u, 255u}) assert(!accepts(valid, 32, 8, button));
    auto reject = [&](bool Orbit::XwaylandMoveContext::*field, bool value) {
        auto c = valid; c.*field = value; assert(!accepts(c));
    };
    reject(&Orbit::XwaylandMoveContext::leftHeld, false);
    reject(&Orbit::XwaylandMoveContext::inputHeld, false);
    reject(&Orbit::XwaylandMoveContext::locked, true);
    reject(&Orbit::XwaylandMoveContext::mapped, false);
    reject(&Orbit::XwaylandMoveContext::visible, false);
    reject(&Orbit::XwaylandMoveContext::focused, false);
    reject(&Orbit::XwaylandMoveContext::ordinaryWorkspace, false);
    reject(&Orbit::XwaylandMoveContext::pointerInside, false);
    reject(&Orbit::XwaylandMoveContext::dragActive, true);
}
