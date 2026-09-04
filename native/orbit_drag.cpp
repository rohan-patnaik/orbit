#define WLR_USE_UNSTABLE

#include <linux/input-event-codes.h>

#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/protocols/GlobalShortcuts.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <stdexcept>

inline HANDLE PHANDLE = nullptr;

namespace {
constexpr double TOP_EDGE_THRESHOLD = 6.0;

CHyprSignalListener mouseMoveListener;
CHyprSignalListener mouseButtonListener;
CHyprSignalListener tickListener;

PHLWINDOWREF armedWindow;
bool         armed       = false;
bool         pendingSnap = false;

PHLMONITOR monitorAt(const Vector2D& point) {
    for (const auto& monitor : State::monitorState()->monitors()) {
        if (!monitor)
            continue;
        const auto& origin = monitor->m_position;
        const auto& size   = monitor->m_size;
        if (point.x >= origin.x && point.x < origin.x + size.x && point.y >= origin.y && point.y < origin.y + size.y)
            return monitor;
    }
    return nullptr;
}

void disarm() {
    armed = false;
    armedWindow.reset();
}

void updateTopEdgeArm() {
    if (!g_layoutManager || !Pointer::mgr()) {
        disarm();
        return;
    }

    const auto& controller = g_layoutManager->dragController();
    if (!controller || controller->mode() != MBIND_MOVE || !controller->dragThresholdReached()) {
        disarm();
        return;
    }

    const auto target = controller->target();
    const auto window = target ? target->window() : nullptr;
    if (!Desktop::View::validMapped(window)) {
        disarm();
        return;
    }

    const auto cursor  = Pointer::mgr()->position();
    const auto monitor = monitorAt(cursor);
    if (!monitor || cursor.y > monitor->m_position.y + TOP_EDGE_THRESHOLD) {
        disarm();
        return;
    }

    armed       = true;
    armedWindow = window;
}

void scheduleSnapPicker(const IPointer::SButtonEvent& event) {
    if (event.button != BTN_LEFT || event.state != WL_POINTER_BUTTON_STATE_RELEASED)
        return;

    const auto window = armedWindow.lock();
    const bool shouldOpen = armed && Desktop::View::validMapped(window);
    disarm();
    if (shouldOpen)
        pendingSnap = true;
}

void openSnapPickerOnNextTick() {
    if (!pendingSnap)
        return;
    pendingSnap = false;
    if (!PROTO::globalShortcuts)
        return;
    PROTO::globalShortcuts->sendGlobalShortcutEvent("omarchy-window-switcher", "snap", true);
    PROTO::globalShortcuts->sendGlobalShortcutEvent("omarchy-window-switcher", "snap", false);
}
} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string runningHash = __hyprland_api_get_hash();
    const std::string clientHash  = __hyprland_api_get_client_hash();
    if (runningHash != clientHash)
        throw std::runtime_error("Orbit drag bridge was built for a different Hyprland ABI");

    mouseMoveListener = Event::bus()->m_events.input.mouse.move.listen([](Vector2D, Event::SCallbackInfo&) { updateTopEdgeArm(); });
    mouseButtonListener = Event::bus()->m_events.input.mouse.button.listen(
        [](IPointer::SButtonEvent event, Event::SCallbackInfo&) { scheduleSnapPicker(event); });
    tickListener = Event::bus()->m_events.tick.listen([] { openSnapPickerOnNextTick(); });

    return {
        "orbit-drag",
        "Opens Orbit Snap Layouts after a native window drag reaches the top edge.",
        "Rohan Patnaik",
        "0.5.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    pendingSnap = false;
    disarm();
    mouseMoveListener.reset();
    mouseButtonListener.reset();
    tickListener.reset();
}
