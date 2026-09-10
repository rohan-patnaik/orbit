# Window preview proportions — local review

This change addresses maximized Firefox and T3 Code windows appearing as narrow
tiles in Orbit's Grid view. It is based on Orbit 0.6.1 and has not been published.

## Cause and change

Hyprland allows one covering window per workspace. Orbit's existing activation
handoff releases the outgoing window's internal fullscreen state while preserving
its client state for restoration. The hidden window then acquires a tiled size.
A live capture probe confirmed that both the IPC dimensions and the captured
image become narrow; changing only the card width would distort that image.

Orbit now retains a reduced image of a maximized/fullscreen source before its
handoff. A subsequently demoted window uses that image and its matching dimensions.
The image is eligible only for the same window identity, client mode, floating and
pinned state, workspace, monitor, and display size/scale. Normal windowed layouts
and currently maximized windows use fresh captures. Late captures with the wrong
aspect and callbacks from closed or superseded windows are rejected.

Grid no longer clamps legitimate portrait/ultrawide aspect ratios. WindowCard
fits both live and retained images proportionally; Quickshell's
[`constraintSize`](https://quickshell.org/docs/v0.2.1/types/Quickshell.Wayland/ScreencopyView/)
constrains implicit sizing and does not prevent distortion when an item is
explicitly stretched to a different rectangle.

Retained images are bounded to 24 entries of at most 640×400 pixels. That caps
their RGBA payload at 24.6 MB, excluding Qt/GPU overhead. They are held only in
memory, evicted by capture recency, and pruned when windows close. Temporary full
capture buffers still disappear with the overlay. Ordinary tiled quick taps
retain their capture-free path. A maximized/fullscreen source gets a 40 ms capture
head start even when the destination needs no resize; ordinary tiled activation
keeps its initial 16 ms timer.

## Verification

- `bash scripts/check.sh`: passed plugin validation, **95 tests**, QML lint,
  formatting, and whitespace checks. Existing environment/type-resolution lint
  warnings remain; the command exits successfully.
- The real offscreen QML test passes 58 assertions, including loading a retained
  image with a 10:7 ratio, checking its painted proportions, and checking the
  actual Grid card geometry. The existing seven-card Flip and twelve-card Grid
  allocation/lifetime bounds still pass.
- Live Firefox, T3 Code, and ChatGPT switching restored each window to
  **1896×1019**, with maximized state 1. Subsequent previews retained that ratio
  while the hidden apps had narrower tiled dimensions.
- Real 700×490 and 281×490 floating test windows on the 150% scaled secondary
  display appeared alongside the maximized apps with their own proportions.
  Circular content stayed round. The grid adapted to multiple rows.
- A floating test window was maximized, captured, and temporarily demoted to
  700×490 while retaining client mode 1. Its full preview remained eligible.
  Explicitly clearing both modes immediately restored the live 700×490 preview.
- Native desktop Alt+Tab and reverse switching, latched selection/acceptance,
  and cancellation were exercised. Compositor state and Orbit's diagnostics were
  checked after switching. Cua Driver required its direct Wayland backend; its
  default service exposed no native windows, and explicit main-monitor captures
  supplemented its desktop snapshots.
- Closing both disposable test windows removed the retained test image: the cache
  fell from four entries to the three surviving apps. The picker and activation
  transaction were closed. No preview loading, grab, binding-loop, or JavaScript
  runtime errors appeared in the final shell log; `hyprctl configerrors` was empty.

Desktop images were inspected locally and are not committed with the source.
The local installation preserves the user's separate Wispr filtering change.
The native compositor bridge and release version are unchanged.

## Limits

The image cache is session-local. After a shell restart or eviction, an already
hidden window uses its available live capture until it has been shown and
captured by Orbit. Orbit does not activate or resize hidden apps to populate this
cache. Background previews are still images from the last valid capture, not
continuous video. A failed or late capture leaves the existing live fallback;
the capture head start is bounded and is not a guarantee for every stalled app
or GPU. This validation does not claim new latency or memory benchmark results.
