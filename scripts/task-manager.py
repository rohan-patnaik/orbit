#!/usr/bin/env python3
"""Orbit's optional, current-theme Task Manager; disabled/unavailable uses btop."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

PLUGIN_ID = 'io.github.rohan-patnaik.window-switcher'


def enabled(config):
    if not isinstance(config, dict) or not isinstance(config.get('plugins'), list):
        return False
    for entry in config['plugins']:
        if not isinstance(entry, dict) or entry.get('id') != PLUGIN_ID:
            continue
        if entry.get('enabled') is False:
            return False
        features = entry.get('features')
        return not isinstance(features, dict) or features.get('taskManager') is not False
    return False


def configured():
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'omarchy/shell.json'
    try:
        return enabled(json.loads(config.read_text()))
    except (OSError, ValueError):
        return False


def prepare_preferences():
    if not shutil.which('xfconf-query'):
        return
    def query(property, *args):
        return subprocess.run(['xfconf-query', '-c', 'xfce4-taskmanager', '-p', property, *args],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3).returncode
    try:
        if query('/prompt-terminate-task', '--create', '-t', 'bool', '-s', 'true'):
            print('Could not save task termination confirmation preference.', file=sys.stderr)
        for property in ('/interface/show-filter', '/columns/column-state',
                         '/columns/column-pid', '/columns/column-cpu', '/columns/column-rss'):
            if query(property):
                query(property, '--create', '-t', 'bool', '-s', 'true')
    except (OSError, subprocess.SubprocessError) as error:
        print(f'Task Manager preferences unavailable: {error}', file=sys.stderr)


def launch_command():
    # Read on every invocation: a feature-only settings save needs no reload.
    if not configured() or not shutil.which('xfce4-taskmanager'):
        return ['omarchy-launch-tui', 'btop']
    prepare_preferences()
    theme = Path(__file__).with_name('task-manager-theme.py')
    themed = False
    try:
        themed = subprocess.run([sys.executable, str(theme)], timeout=15).returncode == 0
    except (OSError, subprocess.SubprocessError) as error:
        print(f'Task Manager theme unavailable: {error}', file=sys.stderr)
    command = ['xfce4-taskmanager']
    if themed:
        command = ['env', 'GTK_THEME=OmarchyTaskManager', *command]
    # The standard Omarchy app scope retains normal session integration.
    if shutil.which('uwsm-app'):
        command = ['uwsm-app', '--', *command]
    return command


if __name__ == '__main__':
    command = launch_command()
    os.execvp(command[0], command)
