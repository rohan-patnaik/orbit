#define WLR_USE_UNSTABLE

#include "DragTracker.hpp"
#include <linux/input-event-codes.h>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/desktop/Workspace.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/managers/EventManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/helpers/MiscFunctions.hpp>
#include <chrono>
#include <stdexcept>

inline HANDLE PHANDLE = nullptr;

namespace {
using GestureEvent = Orbit::DragTracker::Event;
constexpr auto SAMPLE_INTERVAL = std::chrono::milliseconds(16);
Orbit::DragTracker tracker;
CHyprSignalListener motionListener, buttonListener, keyListener, fullscreenListener;
SP<SHyprCtlCommand> statusCommand;
SP<SHyprCtlCommand> readinessCommand;
SP<CEventLoopTimer> sampleTimer;
std::string lastSample;
std::string pendingEnd;
uint64_t updates = 0, releases = 0, cancels = 0;
bool sampleScheduled = false;
unsigned heldAltKeys = 0;
bool nextFunctionRegistered = false, previousFunctionRegistered = false;

int switchStep(int direction) {
    // Invoked by the normal Hyprland binding dispatcher, not a raw Tab hook:
    // session locks, shortcut inhibitors, submaps and repeat policy still apply.
    // Press, Escape and Alt-up share socket2 ordering, unlike Wayland globals.
    g_pEventManager->postEvent({"orbitswitchstep", std::format(R"({{"protocol":1,"step":{}}})", direction)});
    return 0;
}

void armSample() {
    if (sampleTimer && !sampleScheduled) {
        sampleScheduled = true;
        sampleTimer->updateTimeout(SAMPLE_INTERVAL);
    }
}

void emit(const char* phase, const std::string& payload) {
    if (!g_pEventManager || payload.empty())
        return;
    g_pEventManager->postEvent({"orbitdrag", std::format(R"({{"phase":"{}","session":{},"protocol":1,{}}})", phase, tracker.session, payload)});
}

std::string snapshot(PHLWINDOW window) {
    const auto cursor = Pointer::mgr()->position();
    const auto monitor = State::monitorState()->query().vec(cursor).run();
    if (!monitor || !Desktop::View::validMapped(window) || !window->m_workspace || !window->layoutTarget())
        return {};
    const auto box = window->layoutTarget()->position();
    const auto modes = Fullscreen::controller()->getFullscreenModes(window);
    // m_size is logical and already transformed; never scale it twice.
    return std::format(
        R"("x":{},"y":{},"monitor":{{"id":{},"name":"{}","x":{},"y":{},"logicalWidth":{},"logicalHeight":{},"scale":{},"reserved":[{},{},{},{}]}},"window":{{"address":"0x{:x}","workspaceId":{},"monitorId":{},"positionX":{},"positionY":{},"previewWidth":{},"previewHeight":{},"fullscreenState":{},"clientFullscreenState":{},"floating":{}}})",
        cursor.x, cursor.y, monitor->m_id, escapeJSONStrings(monitor->m_name), monitor->m_position.x, monitor->m_position.y,
        monitor->m_size.x, monitor->m_size.y, monitor->m_scale,
        monitor->m_reservedArea.left(), monitor->m_reservedArea.top(), monitor->m_reservedArea.right(), monitor->m_reservedArea.bottom(),
        reinterpret_cast<uintptr_t>(window.get()), window->m_workspace->m_id, monitor->m_id, box.x, box.y, box.w, box.h,
        static_cast<int>(modes.internal), static_cast<int>(modes.client), window->m_isFloating);
}

void sample() {
    sampleScheduled = false;
    if (!pendingEnd.empty()) {
        emit("end", pendingEnd);
        pendingEnd.clear();
    }
    const auto* controller = g_layoutManager ? g_layoutManager->dragController().get() : nullptr;
    const auto target = controller ? controller->target() : nullptr;
    const auto window = target ? target->window() : nullptr;
    const bool moving = controller && controller->mode() == MBIND_MOVE && controller->dragThresholdReached()
        && Desktop::View::validMapped(window);
    const auto event = tracker.sample(reinterpret_cast<uintptr_t>(window.get()), moving);
    if (event == GestureEvent::Cancel) {
        ++cancels;
        emit("cancel", lastSample);
    } else if (event == GestureEvent::Move) {
        lastSample = snapshot(window);
        ++updates;
        emit("move", lastSample);
    }
    if (moving)
        armSample();
}

void cleanup() {
    if (nextFunctionRegistered)
        HyprlandAPI::removeLuaFunction(PHANDLE, "orbit", "next");
    if (previousFunctionRegistered)
        HyprlandAPI::removeLuaFunction(PHANDLE, "orbit", "previous");
    nextFunctionRegistered = previousFunctionRegistered = false;
    motionListener.reset();
    buttonListener.reset();
    keyListener.reset();
    fullscreenListener.reset();
    if (g_pEventManager)
        g_pEventManager->postEvent({"orbitswitchfallback", R"({"protocol":1})"});
    if (tracker.cancel() == GestureEvent::Cancel)
        emit("cancel", lastSample);
    if (sampleTimer) {
        sampleTimer->cancel();
        if (g_pEventLoopManager)
            g_pEventLoopManager->removeTimer(sampleTimer);
        sampleTimer.reset();
    }
    if (statusCommand)
        HyprlandAPI::unregisterHyprCtlCommand(PHANDLE, statusCommand);
    statusCommand.reset();
    if (readinessCommand)
        HyprlandAPI::unregisterHyprCtlCommand(PHANDLE, readinessCommand);
    readinessCommand.reset();
}
} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("Orbit drag bridge was built for a different Hyprland ABI");
    if (!g_pEventLoopManager)
        throw std::runtime_error("Orbit drag bridge requires Hyprland's event loop");
    try {
        nextFunctionRegistered = HyprlandAPI::addLuaFunction(handle, "orbit", "next", [](lua_State*) { return switchStep(1); });
        previousFunctionRegistered = HyprlandAPI::addLuaFunction(handle, "orbit", "previous", [](lua_State*) { return switchStep(-1); });
        if (!nextFunctionRegistered || !previousFunctionRegistered)
            throw std::runtime_error("Orbit bridge could not register ordered switch shortcuts");
        sampleTimer = makeShared<CEventLoopTimer>(std::nullopt, [](SP<CEventLoopTimer>, void*) { sample(); }, nullptr);
        g_pEventLoopManager->addTimer(sampleTimer);
        statusCommand = HyprlandAPI::registerHyprCtlCommand(handle, SHyprCtlCommand{
            .name = "orbit-drag-status", .exact = true,
            .fn = [](eHyprCtlOutputFormat, std::string) {
                return std::format(R"({{"protocol":1,"session":{},"dragging":{},"updates":{},"releases":{},"cancels":{},"last":{{{}}}}})",
                    tracker.session, tracker.active != 0, updates, releases, cancels, lastSample);
            },
        });
        if (!statusCommand)
            throw std::runtime_error("Orbit drag bridge could not register diagnostics");
        readinessCommand = HyprlandAPI::registerHyprCtlCommand(handle, SHyprCtlCommand{
            .name = "orbit-window-ready", .exact = false,
            .fn = [](eHyprCtlOutputFormat, std::string request) {
                const auto separator = request.find(' ');
                if (separator == std::string::npos)
                    return std::string{R"({"protocol":1,"supported":false})"};
                const auto address = request.substr(separator + 1);
                // Resolve against live objects; never dereference a caller's address.
                for (const auto& window : Desktop::viewState()->windows()) {
                    if (!Desktop::View::validMapped(window) || address != std::format("0x{:x}", reinterpret_cast<uintptr_t>(window.get())))
                        continue;
                    const auto committed = window->getReportedSize();
                    const auto expected = window->realToReportSize().floor();
                    const auto modes = Fullscreen::controller()->getFullscreenModes(window);
                    // Wayland's ackedSize is promoted to current only on a surface
                    // commit. Export-buffer dimensions alone do NOT prove this.
                    const bool supported = !window->m_isX11;
                    const bool ready = supported && committed == expected && expected.x > 0 && expected.y > 0;
                    std::string exclusive;
                    for (const auto& weakLayer : g_pInputManager->m_exclusiveLSes) {
                        if (const auto layer = weakLayer.lock()) {
                            if (!exclusive.empty()) exclusive += ',';
                            exclusive += '"' + escapeJSONStrings(layer->m_namespace) + '"';
                        }
                    }
                    return std::format(R"({{"protocol":1,"address":"{}","supported":{},"ready":{},"active":{},"internal":{},"committed":[{},{}],"expected":[{},{}],"exclusiveLayers":[{}]}})",
                        address, supported, ready, Desktop::focusState()->window() == window, static_cast<int>(modes.internal), committed.x, committed.y, expected.x, expected.y, exclusive);
                }
                return std::string{R"({"protocol":1,"supported":false})"};
            },
        });
        if (!readinessCommand)
            throw std::runtime_error("Orbit bridge could not register surface-readiness diagnostics");
        fullscreenListener = Event::bus()->m_events.window.fullscreen.listen([](PHLWINDOW window) {
            // Only an app's real xdg_toplevel fullscreen request, not a
            // compositor shortcut, drag, or Orbit's own internal handoff.
            if (!Desktop::View::validMapped(window) || !window->m_xdgSurface || !window->m_xdgSurface->m_toplevel)
                return;
            const auto request = window->m_xdgSurface->m_toplevel->m_state.requestsFullscreen;
            if (!request.has_value())
                return;
            const auto modes = Fullscreen::controller()->getFullscreenModes(window);
            g_pEventManager->postEvent({"orbitclientfullscreen", std::format(
                R"({{"protocol":1,"address":"0x{:x}","requested":{},"internal":{},"client":{},"floating":{},"pinned":{}}})",
                reinterpret_cast<uintptr_t>(window.get()), request.value(), static_cast<int>(modes.internal),
                static_cast<int>(modes.client), window->m_isFloating, window->m_pinned)});
        });
        motionListener = Event::bus()->m_events.input.mouse.move.listen([](Vector2D, Event::SCallbackInfo&) {
            // This hook precedes Hyprland's own move processing: sample on the
            // next event-loop turn. Do not reset a running gesture's timer.
            armSample();
        });
        buttonListener = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent e, Event::SCallbackInfo&) {
            if (e.button != BTN_LEFT || e.state != WL_POINTER_BUTTON_STATE_RELEASED)
                return;
            const auto target = g_layoutManager->dragController()->target();
            if (tracker.active && target && Desktop::View::validMapped(target->window()))
                lastSample = snapshot(target->window());
            if (tracker.release() == GestureEvent::End) {
                ++releases;
                pendingEnd = lastSample;
                // Deliver after native dragEnd/retile, or it overwrites the snap.
                armSample();
            }
        });
        keyListener = Event::bus()->m_events.input.keyboard.key.listen([](IKeyboard::SKeyEvent e, Event::SCallbackInfo&) {
            if (e.keycode == KEY_LEFTALT || e.keycode == KEY_RIGHTALT) {
                const unsigned bit = e.keycode == KEY_LEFTALT ? 1u : 2u;
                if (e.state == WL_KEYBOARD_KEY_STATE_PRESSED)
                    heldAltKeys |= bit;
                else {
                    heldAltKeys &= ~bit;
                    if (!heldAltKeys)
                        g_pEventManager->postEvent({"orbitswitchrelease", R"({"protocol":1})"});
                }
            }
            if (e.keycode == KEY_ESC && e.state == WL_KEYBOARD_KEY_STATE_PRESSED) {
                g_pEventManager->postEvent({"orbitswitchcancel", R"({"protocol":1})"});
                if (tracker.cancel() == GestureEvent::Cancel) {
                    ++cancels;
                    emit("cancel", lastSample);
                }
            }
        });
    } catch (...) {
        cleanup();
        throw;
    }
    return {"orbit-drag", "Live snap gestures and committed Wayland surface readiness.", "Rohan Patnaik", "0.6.0"};
}

APICALL EXPORT void PLUGIN_EXIT() { cleanup(); }
