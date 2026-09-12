# Orbit 0.6.3

Icons now shows every window of an application, matching Grid and Flip. Previously it grouped windows by application and only allowed selecting the most recently used window in each group.

Each icon keeps its own window address and MRU position. Repeated applications receive numbered labels, and changing views preserves the selected window.

Validation: 98 tests passed, including duplicate-window selection and activation in all three views. Live checks confirmed both Firefox windows appear in Icons, Grid, and Flip. Omarchy plugin validation passed.

## Upgrade

```bash
omarchy plugin update io.github.rohan-patnaik.window-switcher --yes
omarchy restart shell
```

Restart the shell to clear cached QML JavaScript imports. This patch does not change the native bridge or require rebuilding it. Existing installations need to update to receive the fix; marketplace snapshot publication requires maintainer approval.
