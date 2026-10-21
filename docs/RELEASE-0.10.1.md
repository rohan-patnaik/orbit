# Orbit 0.10.1 — Preview, switching and source parity

- Preserve bounded in-memory full-window previews across temporary fullscreen
  demotion, without stretching portrait or ultrawide windows. Invalidate retained
  images when window identity, mode, workspace, monitor or display geometry changes.
- Focus/unhide monocle targets before maximizing them, including other monitors.
  Avoid a resize cover when live geometry already fills the work area.
- Keep Wispr Flow internal windows out of Orbit while dictation remains active.
- Include the guarded XWayland pointer-move adapter previously maintained locally.
  It is enabled only on the inspected Hyprland revision and otherwise remains
  inactive; it preserves native Wayland and unrelated client-message handling.
- Store optional native builds on a configurable mounted artifact drive and reuse
  only source/ABI/SHA-256 verified output. The bridge remains an explicit build/load.

This release incorporates reviewed installed runtime fixes into published source.
It retains the newer public documentation, cover image and regression suites.
Installed manifests and clean Git checkouts must match this exact release commit;
user preferences and native binaries remain outside the tracked source.

No GPU reset, power-policy change, compositor restart or native reload is needed
solely for this source reconciliation. Rebuild the optional bridge after an ABI
change. Marketplace verification is separate from the GitHub release.
