# Orbit 0.6.0 — acceptance checkpoint

This is a historical checkpoint. Subsequent foreground validation is recorded in
the [performance report](PERFORMANCE-2026-09-05.md); the accepted patch and marketplace
update are described in the [0.6.1 release notes](RELEASE-0.6.1.md).

Date: 2026-09-05. Status: **user accepted the candidate and authorized commit/push**.

The user confirmed that the changes work. This authorizes the GitHub commit and
push, not marketplace submission or social posting. The recorded test limitations
below remain accurate; user acceptance does not turn untested cases into test passes.

At the pre-acceptance validation checkpoint, GitHub main and the latest tag were v0.5.0 at
`d9aff9b1acb8b7f22d7260ed80838373f84e74c0`. The local and installed manifest and
loaded native bridge report 0.6.0. No commit, tag, push, marketplace submission,
X draft in an account, or Reddit submission was made during this validation.

## Fresh checks

| Check | Result |
| --- | --- |
| Full `scripts/check.sh` | PASS: 68 tests, zero failures or skipped tests; plugin validation, QML lint/format and diff whitespace checks exit successfully. Existing unqualified-access QML lint warnings remain. |
| Additional acceptance tests | PASS: all 64 boolean-mode combinations with five default choices (320 policies), mode toggles, media-fullscreen priority and floating/pinned exceptions. |
| Display routing | PASS in the executable QML harness: each new switch session selects the pinned main display, falls back to the laptop when absent and returns to main when reconnected. This is not physical hotplug coverage or unplug-while-picker-open coverage. |
| Window closure | PASS: closing the selected entry before acceptance prunes it and chooses a live remaining entry; fewer than two entries closes the picker. The activation Lua transaction makes no changes when its exact target has disappeared or is unmapped. |
| Readiness evidence | PASS: unsupported, invalid or stale-generation readiness cannot count as a committed destination frame. |
| Fresh native compilation | PASS: built to a separate private output, not loaded or installed. Its SHA-256 matches the current source-tree and installed bridge exactly. |
| Installed/source consistency | PASS: all runtime QML, JavaScript, Lua, manifest, native sources and build helper match the candidate. No runtime redeployment was needed. |
| Current desktop startup | PASS: bridge 0.6.0 loaded; `hyprctl configerrors` empty. Both HDMI-A-1 and eDP-1 connected. Saved personal policy remains Maximized with maximize-on-switch enabled. |
| Fresh Cua keyboard integration | BLOCKED, not passed: exact-window background Alt+Tab returned `background_unavailable`. Per-window pixel capture also returned `surface_identity_unproven`. No foreground fallback was attempted without the requested approval. |

Only acceptance tests and documentation were added at this checkpoint. Runtime code,
settings, active application, workspaces, window layout and real pointer were not
intentionally changed. The native compilation output and logs are private local
validation artifacts, not release assets.

## Earlier live evidence retained

The detailed [audit](AUDIT-2026-09-05.md) records the previous installed-build tests.
The final drag, keyboard and ordinary-Firefox logs were reread at this checkpoint;
the clean picker screenshot was visually inspected again. Those are earlier live
results, not new foreground tests in the current desktop session.

- Native move still active while the live picker was visible; selected zone was
  highlighted before release. Final Firefox drops produced Maximized and Fullscreen.
- Top/all four corner triggers, Escape, release outside, scaled laptop geometry,
  halves and Snap Assist were exercised in the earlier audit.
- Real keyboard forward/reverse/cancel, rapid independent gestures, main-display
  picker and an eleven-second hold passed on the final installed build.
- Ordinary Firefox private-window HTML5 fullscreen, continuing muted playback,
  eight switches, exit/reentry, manual unmaximize and personal default restoration
  passed. MPV playback/fullscreen had separate earlier coverage with the limitations
  recorded in the audit.
- Main-display Alt+Tab from the laptop, full-window previews, local application
  icons and exact Codex/T3 focus without a follow-up click had prior live coverage.

## Still needs a live acceptance pass

These are not silently marked green by the unit tests:

1. A fresh foreground drag/Alt+Tab pass on this login, using temporary windows and
   restoring desktop state. Background-only Cua input cannot perform it here.
2. Real YouTube and Twitch fullscreen away/back/exit, plus the local player used
   day-to-day. The local HTML5 fixture is not evidence that every streaming site,
   DRM player or app-specific fullscreen-on-blur policy works.
3. Human titlebar/Super+drag feel in the usual Firefox, Codex and T3 windows, on both
   displays: picker **before release**, all seven choices, cancel, correct target.
4. Physical disconnect/reconnect, especially with a picker open, and relevant
   XWayland applications. Native committed-size proof is Wayland-only; XWayland
   uses a bounded fallback and must not be advertised as universally flicker-free.

## User's short acceptance checklist

- [ ] Drag to top/corners on each display; hover a zone before releasing. Try halves,
  Maximized (`Super+Alt+F`) and Fullscreen (`Super+F`). No Main-and-stack option.
- [ ] Cancel with Escape and by releasing outside; verify no unintended snap.
- [ ] Put one ordinary app on each display. Quick/held/reverse Alt+Tab should include
  both, show the switcher on the main display and leave apps on their original display.
- [ ] Switch Codex/T3/Firefox repeatedly without clicking afterward; check for no
  lost switch, stale old-app screen or visible partial/tiled redraw.
- [ ] Open a normal app: Maximized. Enter a real video player's fullscreen, switch
  away/back, then exit: playback/fullscreen retained during switching, Maximized on exit.
- [ ] Manual floating/tiling/fullscreen and intentionally snapped windows remain
  available; settings cannot disable every normal mode. Review thumbnails/icons too.

## Release gates

Foreground testing approval is not release approval. After the remaining tests and
the user's acceptance: review the exact diff, commit/tag 0.6.0, push GitHub and submit
that exact commit to the Omarchy marketplace. Verify actual catalog publication before
using its canonical listing URL in an availability announcement. Approve the final
social wording separately. Announcement drafts are retained locally, outside this commit.

Live dragging requires the optional native bridge built against the installed
Hyprland ABI. The marketplace does not compile it automatically. This setup requirement
must remain prominent in the release notes and announcement; do not imply a marketplace
update alone enables native dragging for every user.
