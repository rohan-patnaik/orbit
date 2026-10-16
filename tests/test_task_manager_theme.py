import importlib.util
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('orbit_task_manager_theme', ROOT / 'scripts/task-manager-theme.py')
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)

PALETTE = {
    'background': '#1a1b26', 'foreground': '#a9b1d6', 'dark_background': '#16161e',
    'lighter_background': '#24283b', 'bright_foreground': '#c0caf5', 'muted': '#565f89',
    'accent': '#7aa2f7', 'selection': '#2e3c64', 'mode': 'dark',
}


class TaskManagerThemeTests(unittest.TestCase):
    def dialog_rules(self, css):
        return '\n'.join(re.findall(r'messagedialog[^{]*\{[^}]*\}', css))

    def test_confirmation_dialog_is_a_square_raised_panel(self):
        for mode in ('dark', 'light'):
            self.assert_square_panel(theme.render(dict(PALETTE, mode=mode)))

    def assert_square_panel(self, css):
        rules = self.dialog_rules(css)
        self.assertIn('messagedialog.csd decoration', rules)
        self.assertIn('border: 1px solid @tm_line', rules)
        # Adwaita rounds the window background and outer action buttons; any
        # leftover radius shows as light corner specks on the square frame.
        for selector in ('messagedialog.csd.background',
                         'messagedialog.csd .dialog-action-area button:first-child',
                         'messagedialog.csd .dialog-action-area button:last-child'):
            self.assertRegex(css, re.escape(selector) + r'[^{]*\{[^}]*border-radius: 0')

    def test_destructive_yes_uses_the_palette_red_with_a_fallback(self):
        css = theme.render(dict(PALETTE, red='#f7768e'))
        self.assertIn('@define-color tm_danger #f7768e;', css)
        self.assertRegex(self.dialog_rules(css), r'button:last-child \{[^}]*color: @tm_danger')
        self.assertIn('@define-color tm_danger #c74b50;', theme.render(dict(PALETTE)))
        self.assertNotIn('DANGER', css)


if __name__ == '__main__':
    unittest.main()
