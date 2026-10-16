# Orbit 0.8.1 — literal taskbar app names

Includes the default-on themed Task Manager and Desktop controls toggle from
0.8.0. This patch also addresses the marketplace maintainer's context-menu finding:
application names derived from window metadata now use explicit Text.PlainText.
Fallback monograms are plain text too; preview titles already were. Markup-like
app names display literally instead of being interpreted as rich text/resources.

No native bridge, package, privilege, shortcut or power-setting change.
Reload the shell to discard cached QML after updating. Task Manager remains on
by default and retains the off → btop fallback. Marketplace promotion still
requires exact-commit maintainer review; release publication is separate.
