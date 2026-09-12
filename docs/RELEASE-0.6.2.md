# Orbit 0.6.2

Taskbar-minimized apps now appear in Alt-Tab. Previously, Orbit excluded their
special workspaces along with background workspaces, leaving open apps missing
from the switcher.

Selecting a minimized app restores its original workspace, fullscreen/client
state, and pin state before focusing it. Scope filtering uses the original
workspace. Background workspaces remain excluded. Restoration rechecks live
state so activation retries do not move or restore a window twice.

## Validation

Regression tests cover minimized-window scope, background exclusions, saved pin
state, and idempotent activation. Live desktop checks reproduced the missing
ChatGPT entry, then confirmed ChatGPT, T3 Code, and Firefox in the switcher,
restoration of ChatGPT, and forward/reverse switching.

## Upgrade

```bash
omarchy plugin update io.github.rohan-patnaik.window-switcher --yes
omarchy restart shell
```

Restart the shell to clear cached QML JavaScript imports. This patch does not
change the native bridge or require a rebuild of an already compatible bridge.
Marketplace snapshot promotion is separate from the GitHub release.
