# Live Alt+Tab validation — 2026-09-05

Orbit's optimized build is **installed and retained on this desktop**. This report
records the implementation and live validation against baseline `9f9e497`,
Orbit 0.6.0.

## Measured latency

Twenty successful, individually verified quick gestures per condition and build.
Times start at the native Alt-release event received from Hyprland's event socket.
Focus is the first matching compositor `activewindowv2` event. “Hide” is Orbit's
logical overlay close; it is not a physical display measurement.

| Window condition | Baseline focus median / p95 | Final focus median / p95 | Baseline hide median | Final hide median |
| --- | ---: | ---: | ---: | ---: |
| Tiled | 67.55 / 75.51 ms | **21.71 / 22.55 ms** | 102.98 ms | **29.92 ms** |
| Maximized, maximize-on-switch enabled | 66.77 / 72.42 ms | **48.02 / 54.70 ms** | 183.05 ms | **138.26 ms** |
| Fullscreen | 67.27 / 71.84 ms | **47.20 / 58.01 ms** | 183.04 ms | **136.62 ms** |

Tiled focus latency fell about **68%** in this workload. Finalization, including
its retained 32 ms guard, had medians of 64.42, 173.26 and 172.17 ms respectively.
These results do not include the delay inside a physical keyboard or a display's
scanout/pixel response. They are measurements on this machine, not universal bounds.

Separate 1920×1080, 144 fps recordings contain six switches per condition: three
quick taps and three held-Alt selections. Frame analysis and visual inspection
found **no full-screen blank flashes in the final tested transitions**. Quick
tiled taps did not display the picker. For the three held, resizing transitions:

| Captured destination becomes stably visible after release | Baseline median | Final median |
| --- | ---: | ---: |
| Maximized | 284.37 ms | **178.97 ms** |
| Fullscreen | 285.08 ms | **183.22 ms** |

These are capture-based estimates, quantized to approximately 6.94 ms per frame.
Analysis identifies the colored fixture's destination over a central image region
and requires it to remain visible through the observation window. This avoids
counting an early glimpse followed by the outgoing cover as completion. Compositor
focus and a fully revealed image are different events. An unresized first switch
is intentionally excluded from the three-transition resize comparison. This does
not establish zero flicker on every app, monitor, refresh rate, or unsampled frame.

## Resource measurements

Resource intervals ran with tracing and recording disabled. CPU is the entire
Quickshell process plus its reaped child processes, expressed as a percentage of
one CPU core. The bar and other plugins share this process.

| Controlled workload | Baseline shell + children | Final confirmation shell + children |
| --- | ---: | ---: |
| 30 quick tiled switches over about 9.91 s | 19.07% + 6.66% = **25.73%** | 2.52% + 5.14% = **7.67%** |
| Native Grid picker held, measured for 10 s after settling | 0.40% + 3.40% = **3.80%** | 0.10% + 0.20% = **0.30%** |
| 30 Flip cycles with six windows over about 4.81 s | 8.31% + 3.53% = **11.84%** | 1.45% + 0% = **1.45%** |

The repeated-switch workload used about **70% less CPU** in the final confirmation;
a preceding run of the same ordinary switching path measured a 73% reduction.
Flip cycling used about 88% less. This is workload CPU, not a claim that total
computer CPU or battery consumption falls by those percentages.

A separate trace of an 11.2-second native Alt hold counted **75 modifier queries
before and zero after**, with the picker remaining open. Removing those recurring
processes is directly verified. Closed-picker idle sampling of the revised build
showed no additional shell CPU ticks over eight seconds; tick resolution and other
plugins prevent interpreting that as mathematically zero cost.

RSS/PSS and DRM counters are retained in the raw results. Fresh-shell samples
suggested modest memory reductions, but the shared shell's caches and later
reclamation varied substantially. **No reliable Orbit-specific RAM, GPU-memory,
energy or battery-life reduction is claimed.** DRM values are diagnostic snapshots,
not independently validated per-Orbit GPU utilization measurements.

## Changes retained

- Ordinary activation begins after 16 ms and advances on confirmation for the
  exact destination and generation. Resize handoffs keep the 40 ms capture head
  start, 80 ms rendering guard, and bounded fallback. Overlapping activation or
  readiness processes are prevented; known unsupported readiness stops polling
  during fallback.
- Native gestures wait 75 ms after the client query before displaying the picker.
  Alt release can activate immediately during that interval. Already-released
  queued gestures also skip presentation. Fast taps avoid thumbnail allocation
  and the transient picker flash; held selection remains available.
- The switcher and outgoing cover have narrowly scoped Hyprland layer rules that
  disable compositor fades. Other desktop surfaces keep their existing animation
  policy. The cover cannot display before capture content exists; its cached image
  continues updating through the capture head start, then freezes before the first
  activation transaction can resize the source.
- Ordinary tiled activation allocates no full-screen handoff capture. A resize
  cover is allocated only when the source/target/workspace policy can require it.
- Native Alt holds use ordered release/cancel events without modifier polling.
  Bridge unload enables the polling fallback, including during an existing hold.
- Flip retains preview identities, limits actual cards to seven, and updates
  selection immediately. Retaining the old 120 ms animations initially increased
  rendering cost; live measurements caught this and the animations were removed.
- Grid left/right navigation crosses its 12-window page boundary. Application
  metadata is resolved once per application identity per snapshot.
- Escape clears queued gestures even while the prior activation finalizes. If the
  destination closes during activation, Orbit closes the picker, stops pending
  processes and restores a surviving source's fullscreen mode. The selected-title
  binding also tolerates the temporary absence of a selected entry during closure.
- Ordinary pointer motion no longer schedules the native drag sampler. Actual
  titlebar moves and pending gesture ends retain their sampling path.

## Verification and test conditions

- **87 automated tests passed**, plus plugin validation, QML lint/format and diff
  whitespace checks. Existing unqualified-access QML lint warnings remain.
- The actual offscreen QML lifecycle fixture executes **55 assertions** covering
  retained identity, stacking, seven-card Flip and 12-card Grid bounds, navigation
  and release on close. It uses null capture sources, so GPU behavior is established
  separately by live testing. The original baseline fails the retained-identity
  check by recreating all six cards on selection.
- **30 live regression scenarios passed**: rapid independent gestures with 0, 10,
  40 and 90 ms gaps; forward/reverse selection; 14 windows and cross-page arrows;
  cancellation and finalization races; monitor transitions; closing the target
  during a hold and activation; and bridge unload/fallback. Icons intentionally
  groups same-app windows, while Grid and Flip preserve individual entries.
- Additional live checks confirmed that closing a resizing fullscreen destination
  restores the surviving source's internal and client fullscreen state. The initial
  implementation's empty-picker failure was reproduced and fixed.
- An actual Firefox private window played a muted local HTML5 video through eight
  away/back switches, preserved DOM fullscreen, exited to the personal maximized
  default twice, and reentered fullscreen. Playback time continued. Firefox's
  dropped-frame counter increased during hidden/resized playback; this test does
  **not** establish uninterrupted decoding or zero dropped video frames.
- MPV played through four switches each using native Wayland and XWayland. Its
  fullscreen property and playback continued. The user's background launcher
  suppresses new-process fullscreen requests, so MPV's compositor mode was explicitly
  initialized; its voluntary fullscreen exit was not accepted as a valid exit test.
  Firefox, using its existing process, supplies the real enter/exit/reentry check.
- Native titlebar dragging displayed the top/corner picker while the button was
  still held and committed maximized/fullscreen on release. A further 100 ordinary
  pointer movements produced no drag session or updates. This proves behavior,
  not a measured native timer-wakeup or compositor CPU reduction.
- Cua foreground keyboard input was independently verified by compositor events
  and browser state. Its drag result was unverified and did not produce native drag
  events, so it was not counted as success. A temporary output-bound Wayland pointer
  exercised the real compositor move path instead. Timed keyboard gestures used a
  temporary kernel input device because Cua exposes no precise key-hold primitive.
- Baseline and candidate were installed as copies, with a clean shell stop before
  replacing runtime files. The ABI-matched native bridge was unloaded before its
  binary was replaced and reloaded afterward. The compositor stayed running.
  Omarchy also watches documentation/test files: synchronizing those triggered
  extra reloads. A final clean shell restart after all installed files were
  synchronized restored the handlers; future deployments should include those
  files in the stopped-shell synchronization.

Hardware/session: Hyprland 0.56.2, primary HDMI-A-1 1920×1080 at about 144 Hz,
secondary eDP-1 1920×1080 at scale 1.5. Fixture windows were tested on temporary
workspaces 913/914. The original configuration, installed plugin, active window,
monitor/workspace state and pointer were backed up before testing. Temporary test
preferences are removed after validation; the optimized code and original personal
maximize-on-switch/Grid preferences are retained.

The baseline had one early fullscreen attempt that left its picker open before
focus setup was normalized; its trace was not retained and its cause was not
established. It is not included in the successful-trial latency distribution. An
initial recording helper also held **Tab** for 250 ms, reaching key repeat; corrected
runs pulse Tab for 20 ms and hold only Alt. Reported video comparisons require a
single expected destination, and the final latency run passed all 60 trials.

## Limits relative to Windows 11

Grid is the closest existing mode to Windows 11's windows-only Alt+Tab interaction:
MRU order, held cycling, reverse navigation, cancellation and release to activate.
Browser tabs are outside Orbit's scope. Windows also offers Edge-tab inclusion and
thumbnail close buttons. [Microsoft multitasking documentation](https://support.microsoft.com/en-us/windows/how-to-multitask-in-windows-b4fa0333-98f8-ef43-e25c-06d4fb1d6960)

Orbit's previews are deliberately static to avoid continuous capture. Windows DWM
supports dynamically updated thumbnail relationships. Hyprland's real tiling and
fullscreen geometry changes, theme differences and partial Snap Groups prevent an
honest claim of complete 1:1 visual/compositor parity. [DWM thumbnail overview](https://learn.microsoft.com/en-us/windows/win32/dwm/thumbnail-ovw)

**XWayland resizing remains slower:** the bridge cannot prove a committed Wayland
configure for those windows, so their return uses the existing 1.6-second cover
fallback. The live MPV XWayland test reached that fallback and completed successfully.
The fast native-Wayland measurements must not be generalized to this path.

Quickshell's `constraintSize` affects display sizing, not guaranteed smaller capture
buffers. Source resolution therefore still affects memory use even with bounded
preview counts. [Quickshell ScreencopyView documentation](https://quickshell.org/docs/v0.3.1/types/Quickshell.Wayland/ScreencopyView/)

## Evidence and reproduction

Local backups, event traces, process samples, recordings, per-frame CSVs, fixtures
and runner scripts are retained at:

`/home/rohan/.local/state/orbit-backups/live-perf-20260905-32xd1xbb`

Key files under `evidence/`:

- `baseline-benchmark.json`, `verified-benchmark.json`, `summary.json`: timing data.
- `resource-confirmation.json`: resource measurements on the final capture behavior.
- `video-analysis.json`, `*-frames.csv`, `baseline-*.mp4`, `verified-*.mp4`: captured
  transitions and frame analysis. Earlier `candidate`, `final` and `accepted`
  prefixes identify intermediate development runs, including reproduced regressions.
- `regressions.json`, `closed-fullscreen-target.json`, `media.json`, `player.json`,
  `drag.json`: input, closure, media and pointer evidence.
- `desktop-restoration.json`, `installed-final.json`: final cleanup and runtime checks.

Run `bash scripts/check.sh` for local verification and `bash scripts/build-native.sh`
to rebuild the bridge for the installed compositor. The latter does not load it.
`ORBIT_QML_SOURCE_DIR=/path/to/baseline node --test tests/qml-lifecycle.test.cjs`
can reproduce the original preview-identity defect. Live runners control the desktop
and require the fixture/server setup recorded alongside them; they are not passive
unit tests. The pointer helper uses the [wlroots virtual-pointer protocol](https://raw.githubusercontent.com/swaywm/wlr-protocols/master/unstable/wlr-virtual-pointer-unstable-v1.xml).

Native binary SHA-256 retained in the installed build:
`7178bb64904616ab382339a1fddbb049b08ce4af3fe90ded3eadf3e0e9bce80c`.

The user's global `/home/rohan/.codex/AGENTS.md` now authorizes actions reasonably
necessary for an assigned task, including foreground desktop control and required
fallbacks, without repeated permission requests. Its previous text is included in
the backup directory.
