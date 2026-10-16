#!/usr/bin/python3
"""Generate a GTK3 theme selected only by the Task Manager launcher."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

REQUIRED = ('background', 'foreground', 'dark_background', 'lighter_background',
            'bright_foreground', 'muted', 'accent', 'selection')
OPTIONAL = ('darker_background', 'selection_foreground')
HEX = re.compile(r'#[0-9a-fA-F]{6}')

# Adwaita keeps widget geometry, icons and dialog layout; only colours, spacing,
# row density and control shapes below are ours. Lifecycle row highlights, the
# legend dots, the CPU/Memory/Swap label colours and the usage graphs are set by
# the application at a higher CSS priority and intentionally stay native.
TEMPLATE = '''/* Generated from the current Omarchy palette. Task Manager only. */
@import url("resource:///org/gtk/libgtk/theme/Adwaita/BASE");

/* Palette */
@define-color tm_bg BACKGROUND;
@define-color tm_fg FOREGROUND;
@define-color tm_strong BRIGHT_FOREGROUND;
@define-color tm_accent ACCENT;
@define-color tm_selected SELECTION;
@define-color tm_selected_fg SELECTION_FOREGROUND;
@define-color tm_row_selected mix(BACKGROUND, ACCENT, 0.28);
@define-color tm_surface SURFACE;
@define-color tm_field FIELD;
@define-color tm_line MUTED;
@define-color tm_dim mix(FOREGROUND, BACKGROUND, 0.4);
@define-color tm_grid alpha(FOREGROUND, 0.12);
@define-color tm_hover alpha(ACCENT, 0.12);
@define-color tm_on_accent BACKGROUND;

/* Adwaita named colours */
@define-color theme_bg_color @tm_bg;
@define-color theme_fg_color @tm_fg;
@define-color theme_base_color @tm_bg;
@define-color theme_text_color @tm_fg;
@define-color theme_selected_bg_color @tm_row_selected;
@define-color theme_selected_fg_color @tm_strong;
@define-color theme_unfocused_bg_color @tm_bg;
@define-color theme_unfocused_fg_color @tm_fg;
@define-color theme_unfocused_base_color @tm_bg;
@define-color theme_unfocused_text_color @tm_fg;
@define-color theme_unfocused_selected_bg_color @tm_row_selected;
@define-color theme_unfocused_selected_fg_color @tm_strong;
@define-color insensitive_bg_color @tm_bg;
@define-color insensitive_fg_color @tm_dim;
@define-color insensitive_base_color @tm_bg;
@define-color unfocused_insensitive_color @tm_dim;
@define-color borders @tm_line;
@define-color unfocused_borders @tm_line;

/* Window */
window, .background, .background:backdrop, viewport, statusbar {
  background-color: @tm_bg; color: @tm_fg;
}
*:backdrop { color: @tm_fg; }
label:disabled, label:disabled:backdrop { color: @tm_dim; }

/* Native draggable title bar; close is separate from the search field. */
headerbar, headerbar:backdrop {
  background-image: none; background-color: @tm_surface; color: @tm_strong;
  border: none; box-shadow: none; min-height: 32px; padding: 4px 8px;
}
headerbar button.titlebutton {
  background-image: none; background-color: transparent; color: @tm_fg;
  border: none; box-shadow: none; min-width: 24px; min-height: 24px;
}
headerbar button.titlebutton:hover { background-color: @tm_hover; }
headerbar button.titlebutton.close:hover { background-color: #c74b50; color: #ffffff; }

/* Toolbar: a quiet band holding the search field */
toolbar, toolbar:backdrop {
  background-color: @tm_surface; color: @tm_fg;
  padding: 6px 8px; border-bottom: 1px solid @tm_line;
}
toolbar button, toolbar button:backdrop {
  background-image: none; background-color: transparent;
  border: 1px solid transparent; border-radius: 6px; box-shadow: none;
  color: @tm_fg; min-width: 24px; min-height: 24px; padding: 3px;
  -gtk-icon-shadow: none;
}
toolbar button:hover { background-color: @tm_hover; }
toolbar button:active, toolbar button:checked {
  background-color: @tm_selected; color: @tm_selected_fg;
}

/* Search and other text fields */
entry, entry:backdrop, spinbutton, spinbutton:backdrop {
  background-image: none; background-color: @tm_field; color: @tm_fg;
  border: 1px solid @tm_line; border-radius: 8px; box-shadow: none;
  min-height: 30px; padding-left: 8px; padding-right: 8px;
  caret-color: @tm_accent;
}
entry:focus, spinbutton:focus {
  border-color: @tm_accent; box-shadow: 0 0 0 1px alpha(@tm_accent, 0.35);
}
entry image { color: @tm_dim; -gtk-icon-style: symbolic; }
entry image.right { color: #8a8a8a; -gtk-icon-transform: scale(0.8); }
entry image:hover { color: @tm_fg; }
entry selection, textview text selection {
  background-color: @tm_accent; color: @tm_on_accent;
}
spinbutton button, spinbutton button:backdrop {
  background-color: transparent; border: none; color: @tm_fg;
}
textview text { background-color: @tm_bg; color: @tm_fg; }

/* Graph band: the graphs draw their own outline, so the frame stays bare */
paned > box.vertical > box.horizontal { margin-left: 8px; margin-right: 8px; }
frame { margin-top: 8px; }
frame > border { border: none; padding: 0; }
paned > box.vertical > box.horizontal > box > box > label {
  margin-top: 4px; margin-bottom: 6px;
}
paned > separator {
  background-image: none; background-color: @tm_line;
  min-height: 1px; min-width: 1px; margin: 4px 0; -gtk-icon-source: none;
}

/* Process table */
scrolledwindow { border: none; }
treeview.view, treeview.view:backdrop {
  background-color: @tm_bg; color: @tm_fg;
  border-left-color: @tm_grid; border-top-color: @tm_bg;
  -GtkTreeView-vertical-separator: 6px;
  -GtkTreeView-horizontal-separator: 10px;
  -GtkTreeView-grid-line-width: 1;
  font-feature-settings: "tnum";
  outline-style: solid; outline-width: 1px; outline-offset: -1px;
  outline-color: alpha(@tm_accent, 0.6); -gtk-outline-radius: 3px;
}
treeview.view:hover { background-color: @tm_hover; }
treeview.view:selected, treeview.view:selected:focus,
treeview.view:selected:backdrop, treeview.view:selected:hover {
  background-color: @tm_row_selected; color: @tm_strong;
}
treeview.view header button, treeview.view header button:backdrop {
  background-image: none; background-color: @tm_surface; color: @tm_dim;
  font-weight: 600; padding: 6px 10px; border-radius: 0;
  border-style: none solid solid none; border-width: 1px;
  border-color: @tm_grid @tm_grid @tm_line @tm_grid;
  text-shadow: none; box-shadow: none;
}
treeview.view header button:last-child { border-right-style: none; }
treeview.view header button:hover {
  background-color: mix(@tm_surface, @tm_fg, 0.06); color: @tm_fg;
}
treeview.view header button:active { background-color: @tm_selected; color: @tm_fg; }
treeview.view header button arrow, treeview.view header button image {
  color: @tm_accent; -gtk-icon-shadow: none;
}

/* Scrollbars: slim, visible only as a line of the text colour */
scrollbar, scrollbar:backdrop { background-color: transparent; border: none; }
scrollbar slider, scrollbar slider:backdrop {
  background-color: alpha(@tm_fg, 0.3); border: 3px solid transparent;
  border-radius: 8px; background-clip: padding-box; min-width: 6px; min-height: 40px;
}
scrollbar slider:hover { background-color: alpha(@tm_fg, 0.5); }
scrollbar slider:active { background-color: @tm_accent; }

/* Legend */
paned > box.vertical > box.horizontal > box > label { color: @tm_dim; }

/* Context menus */
menu, .menu, .context-menu, menu:backdrop {
  background-color: @tm_surface; color: @tm_fg;
  border: 1px solid @tm_line; border-radius: 6px; padding: 4px 0;
}
menu menuitem, menu menuitem:backdrop {
  padding: 6px 12px; min-height: 20px; color: @tm_fg; background: none;
}
menu menuitem:hover { background-color: @tm_accent; color: @tm_on_accent; }
menu menuitem:disabled { color: @tm_dim; }
menu menuitem arrow { color: @tm_dim; min-width: 16px; min-height: 16px; }
menu menuitem:hover arrow { color: @tm_on_accent; }
menu separator { background-color: @tm_line; margin: 4px 0; min-height: 1px; }

/* Buttons and dialogs */
button, button:backdrop {
  background-image: none; background-color: @tm_surface; color: @tm_fg;
  border: 1px solid @tm_line; border-radius: 6px; padding: 4px 14px;
  text-shadow: none; box-shadow: none; -gtk-icon-shadow: none;
  outline-color: alpha(@tm_accent, 0.6); outline-offset: -3px;
}
button:hover { background-color: mix(@tm_surface, @tm_fg, 0.08); color: @tm_strong; }
button:active, button:checked { background-color: @tm_selected; color: @tm_selected_fg; }
button:disabled, button:disabled:backdrop {
  background-color: @tm_bg; color: @tm_dim; border-color: alpha(@tm_line, 0.5);
}
button.suggested-action, button.default {
  background-color: @tm_accent; color: @tm_on_accent; border-color: @tm_accent;
}
messagedialog, messagedialog .titlebar, messagedialog.csd .titlebar, dialog, dialog .titlebar {
  background-color: @tm_bg; color: @tm_fg; border: none; box-shadow: none;
}
messagedialog .dialog-action-area button, messagedialog.csd .dialog-action-area button {
  border-radius: 0; border-style: solid none none solid; border-color: @tm_line;
  padding: 10px 16px; background-color: @tm_bg; color: @tm_fg;
  outline-style: solid; outline-width: 1px; outline-offset: -4px; -gtk-outline-radius: 4px;
}
messagedialog .dialog-action-area button:first-child { border-left-style: none; }
messagedialog .dialog-action-area button:hover { background-color: @tm_hover; color: @tm_strong; }
messagedialog .dialog-action-area button:active { background-color: @tm_selected; }
messagedialog .dialog-action-area button:focus { color: @tm_accent; }
messagedialog label.title { color: @tm_strong; }

/* Settings dialog widgets */
notebook > header { background-color: @tm_surface; border-color: @tm_line; }
notebook > header tab { color: @tm_dim; padding: 6px 12px; }
notebook > header tab:checked { color: @tm_fg; box-shadow: inset 0 -2px @tm_accent; }
notebook > stack { background-color: @tm_bg; }
check, radio, check:backdrop, radio:backdrop {
  background-image: none; background-color: @tm_field; border-color: @tm_line;
  box-shadow: none; -gtk-icon-shadow: none;
}
check:checked, radio:checked, check:checked:backdrop, radio:checked:backdrop {
  background-color: @tm_accent; border-color: @tm_accent; color: @tm_on_accent;
}
switch, switch:backdrop { background-image: none; background-color: @tm_field; border-color: @tm_line; }
switch:checked { background-color: @tm_accent; border-color: @tm_accent; }
switch slider { background-image: none; background-color: @tm_strong; border-color: @tm_line; box-shadow: none; }
combobox button, combobox button:backdrop { background-color: @tm_field; }
separator { background-color: @tm_line; }

/* Tooltips */
tooltip, tooltip.background, tooltip.csd {
  background-color: @tm_surface; color: @tm_fg;
  border: 1px solid @tm_line; border-radius: 6px; box-shadow: none;
}
tooltip * { background-color: transparent; color: @tm_fg; }
'''


def luminance(colour):
    red, green, blue = (int(colour[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def mix(colour, other, amount):
    channels = (round(int(colour[i:i + 2], 16) * (1 - amount) + int(other[i:i + 2], 16) * amount)
                for i in (1, 3, 5))
    return '#%02x%02x%02x' % tuple(channels)


def nearest(palette, direction):
    """Closest distinct palette background one step lighter (+1) or darker (-1)."""
    base = luminance(palette['background'])
    steps = []
    for key in ('dark_background', 'lighter_background', 'darker_background'):
        colour = palette.get(key)
        if colour is None:
            continue
        delta = (luminance(colour) - base) * direction
        if delta >= 0.015:
            steps.append((delta, colour))
    return min(steps)[1] if steps else None


def render(palette):
    for key in REQUIRED + tuple(k for k in OPTIONAL if k in palette):
        if not HEX.fullmatch(palette.get(key, '')):
            raise ValueError(f'Missing or invalid palette colour: {key}')
    mode = palette.get('mode')
    if mode not in ('light', 'dark'):
        raise ValueError('Missing or invalid palette mode')
    base = 'gtk-dark.css' if mode == 'dark' else 'gtk.css'
    raised, sunken = (1, -1) if mode == 'dark' else (-1, 1)
    # Raised chrome (toolbar, headers) steps away from the canvas toward the
    # foreground; fields step the other way. Themes whose names do not match
    # their luminance (e.g. a "lighter" background that is darker) still work.
    surface = nearest(palette, raised) or mix(palette['background'], palette['foreground'], 0.07)
    field = nearest(palette, sunken) or palette['background']
    values = dict(palette, surface=surface, field=field,
                  selection_foreground=palette.get('selection_foreground', palette['bright_foreground']))
    css = TEMPLATE.replace('BASE', base)
    # Longest first so BACKGROUND never corrupts DARK_BACKGROUND, etc.
    for key in sorted(REQUIRED + ('surface', 'field', 'selection_foreground'), key=len, reverse=True):
        css = css.replace(key.upper(), values[key])
    return css


def main():
    result = subprocess.run(['omarchy-theme-color', '--all'], check=True,
                            capture_output=True, text=True, timeout=10)
    palette = dict(line.split('\t', 1) for line in result.stdout.splitlines() if '\t' in line)
    css = render(palette)
    data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    folder = data / 'themes/OmarchyTaskManager/gtk-3.0'
    folder.mkdir(parents=True, exist_ok=True)
    # GTK may request the dark variant from its native preference.
    for name, content in [('gtk.css', css), ('gtk-dark.css', '@import url("gtk.css");\n')]:
        target = folder / name
        if target.exists() and target.read_text() == content:
            continue
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', dir=folder, delete=False) as output:
                temporary = Path(output.name)
                output.write(content)
            temporary.chmod(0o644)
            temporary.replace(target)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'Task Manager theme unavailable: {error}', file=sys.stderr)
        sys.exit(1)
