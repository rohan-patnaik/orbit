# Orbit 0.10.0 — Task Manager everywhere, rescue keys

- Task Manager and its Terminate/Kill and Settings dialogs open on the focused
  workspace, raised and focused, even under a static `workspace = "1 silent"`
  rule. Its modal dialogs stay in front of the main window when it is clicked.
- Confirmation dialogs are a square, bordered raised panel; **Yes** uses the
  palette red. Fixes the light specks at the dialog's bottom corners.
- Shift+F10 opens the process row menu, alongside right-click and the Menu key,
  without consuming Shift+F10 in other apps.
- Alt+Tab: a native hold whose Alt release was lost now completes after one
  watchdog check instead of leaving the picker open.
- Optional rescue keys (`sudo ./rescue/install.sh`): Ctrl+Alt+Shift+Esc opens a
  text-console rescue screen and Super+Ctrl+Shift+B restarts graphics, both
  below the compositor. See the README's Rescue keys section.

Update Orbit and reload Hyprland. Close and reopen Task Manager once. The rescue
keys are a separate, explicit root install; the plugin itself never elevates.

Investigated without changes: Task Manager's Task column shows command lines
with arguments even with full command lines off (an upstream limitation), and
tree view was rejected as noisier. Under Hyprland's monocle layout GTK is told
every window is maximized, so Task Manager saves that state; the launcher keeps
resetting it, which remains sufficient. Escape still closes the main window
(upstream behaviour).

Verified locally on Hyprland 0.56.2 / Xfce Task Manager 1.6.0 with kernel-level
virtual input: workspace placement, dialog focus and stacking, keyboard menu,
rescue screen, End a task, renderer reload, and one live AMD GPU reset
(MODE2, under a second) on a Ryzen iGPU: Hyprland, Firefox, Electron apps and
Task Manager all survived with no core dumps. Other GPUs and drivers may differ.
