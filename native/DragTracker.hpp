#pragma once
#include <cstdint>

namespace Orbit {
// Only the adapter admits actual compositor move grabs. Content drags, clicks
// and resize grabs must not create a gesture. Escape suppresses until release.
class DragTracker {
  public:
    enum class Event { None, Move, End, Cancel };
    Event sample(uintptr_t window, bool moving) {
        if (!window || !moving) {
            const bool wasActive = active != 0;
            active = suppressed = 0;
            return wasActive ? Event::Cancel : Event::None;
        }
        if (window == suppressed)
            return Event::None;
        if (active != window) {
            active = window;
            ++session;
        }
        return Event::Move;
    }
    Event release() {
        const bool wasActive = active != 0;
        active = suppressed = 0;
        return wasActive ? Event::End : Event::None;
    }
    Event cancel() {
        if (!active)
            return Event::None;
        suppressed = active;
        active = 0;
        return Event::Cancel;
    }
    uintptr_t active = 0;
    uint64_t session = 0;
  private:
    uintptr_t suppressed = 0;
};
} // namespace Orbit
