# Orbit 0.9.0 — Floating and Task Manager window controls

- Super+Z adds **Floating**: a centered, freely movable window at about 60% width
  and 70% height. Selecting it leaves fullscreen and any snap group.
- Task Manager defaults to this floating style, with a draggable native title bar
  and a top-right window-close cross. The smaller grey cross inside search clears
  only the filter. Current Omarchy palette styling and the default-on toggle remain.
- Corrects Hyprland float actions to enable/disable; choosing an already-floating
  window no longer toggles it back into tiling. Naturally floating dialogs retain
  their normal sizes.

Install `xfce4-taskmanager python-gobject` through `omarchy pkg add`, update Orbit,
reload Hyprland and restart the shell once to refresh Snap Layouts. Close/reopen
Task Manager to load its controls. No native bridge rebuild or package binary
patch is required. Without the optional UI bindings, Task Manager still launches
with the vendor controls and a diagnostic; absent Xfce still falls back to btop.

The app-scoped UI overlay is derived from the installed resource on each launch,
retaining translations, process widgets and native actions. Unknown layouts fall
back safely. No changes to global GTK, process termination policy or power settings.

Verified locally on Hyprland 0.56.2 / Xfce Task Manager 1.6.0: centered launch,
title-bar drag, filter and clear, native close, and Floating picker selection.
Public checks: 114 Node tests and 19 Python/Qt tests, plugin validation, QML lint
and formatting. Existing nonfatal QML warnings remain. Marketplace promotion
requires separate maintainer approval after exact-commit verification.
