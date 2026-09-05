#include "../native/DragTracker.hpp"
#include <cassert>
int main() {
    using Event = Orbit::DragTracker::Event;
    Orbit::DragTracker drag;
    assert(drag.sample(0, false) == Event::None);
    assert(drag.sample(12, false) == Event::None); // click/resize/content, not a move
    assert(drag.release() == Event::None);
    assert(drag.sample(12, true) == Event::Move);
    assert(drag.active == 12 && drag.session == 1);
    for (int i = 0; i < 1000; ++i) assert(drag.sample(12, true) == Event::Move);
    assert(drag.session == 1);
    assert(drag.release() == Event::End);
    assert(drag.release() == Event::None);
    assert(drag.sample(13, true) == Event::Move && drag.session == 2);
    assert(drag.cancel() == Event::Cancel);
    assert(drag.sample(13, true) == Event::None); // Escape cannot reopen mid-grab
    assert(drag.release() == Event::None);
    assert(drag.sample(13, true) == Event::Move && drag.session == 3);
    assert(drag.sample(0, false) == Event::Cancel); // window closed or grab lost
    assert(drag.sample(0, false) == Event::None);
}
