# Orbit 0.6.4

Orbit now resolves Chromium-family web-app windows through their installed
launcher URL host/path before falling back to browser heuristics. WhatsApp
uses its own installed logo and identity, and unregistered web apps keep a
monogram instead of being mistaken for Chrome. Desktop-entry absolute icon
paths work, and symbolic artwork gets a contrast backplate in all three views.
Icons remain local; Orbit does not download or bundle application logos.

Taskbar-minimized windows with negative-ID named workspaces and extended saved
workspace/display records are now eligible for Alt-Tab. Selecting one restores
its original workspace; if removed, it recreates that workspace on the saved
connected display. Existing workspaces stay put, unplugged displays are handled,
legacy numeric records work, and restoration retries recheck live state.

Taskbar drag ordering belongs to the taskbar implementation, not Orbit. Orbit
continues to cycle individual windows in MRU order, including duplicate apps.

## Validation

The complete Node suite covers browser/native launcher identity, icon paths,
symbolic contrast, minimize scope and malformed records. Generated restore
transactions run against Lua compositor stubs for existing/removed workspaces,
connected/unplugged monitors and repeated activation. Plugin validation, QML
lint/formatting and whitespace checks pass. No native bridge code changes.

## Upgrade

```bash
omarchy plugin update io.github.rohan-patnaik.window-switcher --yes
omarchy restart shell
```

Restart only the shell to clear cached QML/JavaScript. Applications remain open.
This patch does not require rebuilding an already ABI-compatible native bridge.
GitHub release publication and marketplace snapshot promotion are separate.
