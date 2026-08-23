-- Orbit replaces Omarchy's stock Alt+Tab bindings. Keep the original
-- window-cycle behavior available on Super+Q.
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")

o.bind(
  "ALT + TAB",
  "Orbit next window",
  hl.dsp.global("omarchy-window-switcher:next"),
  { repeating = true }
)

o.bind(
  "ALT + SHIFT + TAB",
  "Orbit previous window",
  hl.dsp.global("omarchy-window-switcher:previous"),
  { repeating = true }
)

o.bind("SUPER + Q", "Focus on next window", hl.dsp.window.cycle_next())
o.bind("SUPER + Q", "Reveal active window on top", hl.dsp.window.bring_to_top())
o.bind("SUPER + SHIFT + Q", "Focus on previous window", hl.dsp.window.cycle_next({ next = false }))
o.bind("SUPER + SHIFT + Q", "Reveal active window on top", hl.dsp.window.bring_to_top())
