import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('orbit_task_manager', ROOT / 'scripts/task-manager.py')
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)


class TaskManagerTests(unittest.TestCase):
    def test_defaults_on_but_explicit_off_and_plugin_disablement_win(self):
        for features in (None, {}, {'grid': False}, {'taskManager': 'false'}):
            self.assertTrue(manager.enabled({'plugins': [{'id': manager.PLUGIN_ID, 'features': features}]}))
        for entry in ({'features': {'taskManager': False}}, {'enabled': False}):
            self.assertFalse(manager.enabled({'plugins': [dict(id=manager.PLUGIN_ID, **entry)]}))
        for config in ({}, [], {'plugins': []}, {'plugins': ['bad']}, {'plugins': [{'id': 'other'}]}):
            self.assertFalse(manager.enabled(config))

    def test_config_rereads_feature_each_time_without_reloading_shell(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, XDG_CONFIG_HOME=tmp):
            config = Path(tmp) / 'omarchy/shell.json'
            config.parent.mkdir()
            for value in (True, False, True):
                config.write_text(json.dumps({'plugins': [{'id': manager.PLUGIN_ID, 'features': {'taskManager': value}}]}))
                self.assertEqual(manager.configured(), value)
            config.write_text('bad JSON')
            self.assertFalse(manager.configured())

    def test_off_or_missing_gui_falls_back_without_mutating_preferences(self):
        for enabled, available in ((False, True), (True, False)):
            with patch.object(manager, 'configured', return_value=enabled), patch.object(manager.shutil, 'which', return_value=available), patch.object(manager, 'prepare_preferences') as preferences:
                self.assertEqual(manager.launch_command(), ['omarchy-launch-tui', 'btop'])
                preferences.assert_not_called()

    def test_theme_failure_retains_native_gui_and_success_is_scoped(self):
        for result in (0, 1):
            with patch.object(manager, 'configured', return_value=True), patch.object(manager.shutil, 'which', return_value=True), patch.object(manager, 'prepare_preferences'), patch.object(manager.subprocess, 'run', return_value=subprocess.CompletedProcess([], result)):
                command = manager.launch_command()
                self.assertEqual(command, ['uwsm-app', '--'] + (['env', 'GTK_THEME=OmarchyTaskManager'] if result == 0 else []) + ['xfce4-taskmanager'])

    def test_preferences_seed_missing_only_and_require_confirmation(self):
        calls = []
        def run(argv, **kwargs):
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 1 if argv[-1] == '/columns/column-state' else 0)
        with patch.object(manager.shutil, 'which', return_value=True), patch.object(manager.subprocess, 'run', side_effect=run):
            manager.prepare_preferences()
        writes = [c for c in calls if '--create' in c]
        self.assertEqual([c[4] for c in writes], ['/prompt-terminate-task', '/window-maximized', '/columns/column-state'])
        self.assertEqual([c[-1] for c in writes], ['true', 'false', 'true'])

    def test_palette_timeout_still_opens_gui(self):
        with patch.object(manager, 'configured', return_value=True), patch.object(manager.shutil, 'which', return_value=True), patch.object(manager, 'prepare_preferences'), patch.object(manager.subprocess, 'run', side_effect=subprocess.TimeoutExpired('theme', 15)):
            self.assertEqual(manager.launch_command(), ['uwsm-app', '--', 'xfce4-taskmanager'])

    def test_native_controls_overlay_is_scoped_to_the_launched_app(self):
        results = [subprocess.CompletedProcess([], 0),
                   subprocess.CompletedProcess([], 0, stdout='/org/xfce/taskmanager/process-window=/data/ui\n')]
        with patch.object(manager, 'configured', return_value=True), patch.object(manager.shutil, 'which', return_value=True), patch.object(manager, 'prepare_preferences'), patch.object(manager.subprocess, 'run', side_effect=results):
            self.assertEqual(manager.launch_command(), ['uwsm-app', '--', 'env', 'GTK_THEME=OmarchyTaskManager',
                'env', 'G_RESOURCE_OVERLAYS=/org/xfce/taskmanager/process-window=/data/ui', 'xfce4-taskmanager'])
