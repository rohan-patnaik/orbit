import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('orbit_rescue', ROOT / 'rescue' / 'orbit_rescue.py')
rescue = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rescue)

CTRL, SHIFT, ALT, SUPER = 29, 42, 56, 125
RCTRL, RSHIFT, RALT = 97, 54, 100
ESC, B = rescue.KEY_ESC, rescue.KEY_B


class ChordTests(unittest.TestCase):
    def test_rescue_chords_need_their_exact_modifiers(self):
        self.assertEqual(rescue.match_combo({CTRL, ALT, SHIFT, ESC}, ESC), 'console')
        self.assertEqual(rescue.match_combo({RCTRL, RALT, RSHIFT, ESC}, ESC), 'console')
        self.assertEqual(rescue.match_combo({SUPER, CTRL, SHIFT, B}, B), 'graphics')
        self.assertIsNone(rescue.match_combo({CTRL, SHIFT, ESC}, ESC), 'Task Manager stays Task Manager')
        self.assertIsNone(rescue.match_combo({CTRL, ALT, SHIFT, SUPER, ESC}, ESC))
        self.assertIsNone(rescue.match_combo({SUPER, CTRL, B}, B))
        self.assertIsNone(rescue.match_combo({CTRL, ALT, SHIFT}, SHIFT))

    def test_watcher_combines_keyboards_ignores_repeat_and_debounces(self):
        fired = []
        watcher = rescue.ChordWatcher(fired.append)
        watcher.handle(3, CTRL, 1)
        watcher.handle(3, ALT, 1)
        watcher.handle(4, SHIFT, 1)
        watcher.handle(4, ESC, 1)
        watcher.handle(4, ESC, 2)
        watcher.handle(4, ESC, 0)
        watcher.handle(4, ESC, 1)
        self.assertEqual(fired, ['console'])
        watcher.handle(3, ALT, 0)
        watcher.handle(3, SUPER, 1)
        watcher.handle(4, B, 1)
        self.assertEqual(fired, ['console', 'graphics'])

    def test_a_removed_keyboard_cannot_leave_modifiers_held(self):
        fired = []
        watcher = rescue.ChordWatcher(fired.append)
        watcher.devices[7] = '/dev/input/event7'
        for code in (CTRL, ALT, SHIFT):
            watcher.handle(7, code, 1)
        with mock.patch.object(rescue.os, 'close'):
            watcher.drop(7)
        watcher.handle(8, ESC, 1)
        self.assertEqual(fired, [])


class SessionTests(unittest.TestCase):
    def test_lock_state_mirrors_omarchy_session_lock_helper(self):
        locked = json.dumps([{'solitaryBlockedBy': ['LOCK']}, {'solitaryBlockedBy': []}])
        unlocked = json.dumps([{'solitaryBlockedBy': ['WINDOWS']}])
        unknown = json.dumps([{'solitaryBlockedBy': ['WORKSPACE']}])
        self.assertIs(rescue.lock_state(locked), True)
        self.assertIs(rescue.lock_state(unlocked), False)
        self.assertIsNone(rescue.lock_state(unknown))
        self.assertIsNone(rescue.lock_state('not json'))

    def test_frozen_compositor_uses_last_known_lock_and_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, 'state', 'session.json')
            rescue.remember({'id': '1', 'locked': False}, path)
            frozen = {'id': '1', 'locked': None}
            self.assertIs(rescue.effective_lock(frozen, path), False)
            self.assertIs(rescue.effective_lock({'id': '2', 'locked': None}, path), True)
            self.assertIs(rescue.effective_lock({'id': '1', 'locked': True}, path), True)
            self.assertIs(rescue.effective_lock(frozen, os.path.join(tmp, 'missing.json')), True)

    def test_locked_menu_offers_no_tasks_or_sign_out(self):
        locked = [action for _, _, action in rescue.menu_items(True)]
        unlocked = [action for _, _, action in rescue.menu_items(False)]
        self.assertEqual(locked, ['return', 'graphics', 'reboot'])
        self.assertEqual(unlocked, ['return', 'tasks', 'graphics', 'signout', 'reboot'])

    def test_rescue_vt_still_finds_the_seat_desktop_session(self):
        listing = ('      1 1000 rohan seat0 1151   user    tty1 no   -\n'
                   '      2 1000 rohan -     1236   manager -    no   -\n')
        self.assertEqual(rescue.seat_session_ids(listing), ['1'])
        replies = {
            ('loginctl', 'show-seat'): mock.Mock(returncode=0, stdout='\n'),
            ('loginctl', 'list-sessions'): mock.Mock(returncode=0, stdout=listing),
            ('loginctl', 'show-session'): mock.Mock(returncode=0, stdout=(
                'Name=rohan\nUser=1000\nVTNr=1\nLockedHint=no\nType=wayland\nSeat=seat0\n')),
        }
        with mock.patch.object(rescue, 'run', side_effect=lambda command, timeout=3: replies[tuple(command[:2])]):
            session = rescue.active_session()
        self.assertEqual((session['id'], session['uid'], session['vt']), ('1', 1000, 1))

    def test_properties_parse_loginctl_output(self):
        self.assertEqual(rescue.parse_properties('Name=rohan\nUser=1000\nbogus\n'),
                         {'Name': 'rohan', 'User': '1000'})


class GraphicsTests(unittest.TestCase):
    def fake_drm(self, tmp):
        drm = Path(tmp, 'drm')
        for card, pci, connectors in (('card0', '0000:01:00.0', {'DP-1': 'disconnected'}),
                                      ('card1', '0000:05:00.0', {'eDP-1': 'connected'})):
            device = Path(tmp, 'pci', pci)
            device.mkdir(parents=True)
            (drm / card).mkdir(parents=True)
            (drm / card / 'device').symlink_to(device)
            for name, status in connectors.items():
                (drm / f'{card}-{name}').mkdir()
                (drm / f'{card}-{name}' / 'status').write_text(status + '\n')
        return drm

    def test_display_gpu_is_the_card_with_a_connected_screen(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(rescue.display_gpu(str(self.fake_drm(tmp))), '0000:05:00.0')

    def test_gpu_reset_targets_only_the_matching_amdgpu_primary_node(self):
        with tempfile.TemporaryDirectory() as tmp:
            debug = Path(tmp, 'dri')
            for node, name in (('0', 'nvidia-drm dev=0000:01:00.0'), ('1', 'amdgpu dev=0000:05:00.0'),
                               ('129', 'amdgpu dev=0000:05:00.0'), ('client-1', 'amdgpu dev=0000:05:00.0')):
                (debug / node).mkdir(parents=True)
                (debug / node / 'name').write_text(name + ' unique=x\n')
                (debug / node / 'amdgpu_gpu_recover').write_text('0\n')
            self.assertEqual(rescue.gpu_recover_file('0000:05:00.0', str(debug)),
                             str(debug / '1' / 'amdgpu_gpu_recover'))
            self.assertIsNone(rescue.gpu_recover_file('0000:01:00.0', str(debug)))

    def test_live_compositor_reloads_its_renderer_before_any_gpu_reset(self):
        session = {'uid': 1000}
        replies = {'version': 'Hyprland 0.56', 'eval hl.dispatch(hl.dsp.force_renderer_reload())': 'ok'}
        with mock.patch.object(rescue, 'hyprland_request', side_effect=lambda uid, r: replies.get(r)), \
                mock.patch.object(rescue, 'reset_gpu') as reset:
            self.assertEqual(rescue.restart_graphics(session), (True, 'Reloaded the desktop renderer.'))
            reset.assert_not_called()

    def test_frozen_compositor_gets_the_gpu_reset(self):
        with mock.patch.object(rescue, 'hyprland_request', return_value=None), \
                mock.patch.object(rescue, 'reset_gpu', return_value=(True, 'Reset GPU x.')) as reset:
            self.assertEqual(rescue.restart_graphics({'uid': 1000}), (True, 'Reset GPU x.'))
            reset.assert_called_once()


class ProcessTests(unittest.TestCase):
    def fake_proc(self, tmp, rows):
        proc = Path(tmp)
        for pid, name, ticks in rows:
            fields = ['S'] + ['0'] * 10 + [str(ticks), '0'] + ['0'] * 8 + ['100'] + ['0'] * 20
            (proc / str(pid)).mkdir()
            (proc / str(pid) / 'stat').write_text(f'{pid} ({name}) ' + ' '.join(fields) + '\n')
            (proc / str(pid) / 'comm').write_text(name + '\n')
        return str(proc)

    def test_task_list_hides_session_critical_processes(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = self.fake_proc(tmp, [(10, 'Hyprland', 5), (11, 'firefox', 9), (12, 'systemd', 1)])
            names = [row['name'] for row in rescue.top_processes(os.getuid(), sample=0.01, proc=proc)]
            self.assertEqual(names, ['firefox'])

    def test_end_process_never_signals_another_users_process(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = self.fake_proc(tmp, [(4242, 'app', 0)])
            with mock.patch.object(rescue.os, 'kill') as kill:
                self.assertFalse(rescue.end_process(4242, os.getuid() + 1, proc=proc))
                kill.assert_not_called()
                self.assertTrue(rescue.end_process(4242, os.getuid(), proc=proc))
                kill.assert_called_once_with(4242, rescue.signal.SIGTERM)


class PackagingTests(unittest.TestCase):
    def test_units_run_the_installed_module_and_stay_up_under_pressure(self):
        daemon = (ROOT / 'rescue' / 'orbit-rescued.service').read_text()
        console = (ROOT / 'rescue' / 'orbit-rescue-console.service').read_text()
        self.assertIn('/usr/local/lib/orbit-rescue/orbit_rescue.py daemon', daemon)
        self.assertIn('OOMScoreAdjust=-1000', daemon)
        self.assertIn(f'TTYPath=/dev/tty{rescue.RESCUE_VT}', console)
        self.assertIn('orbit_rescue.py console', console)
        self.assertEqual(rescue.CONSOLE_UNIT, 'orbit-rescue-console.service')

    def test_hyprland_swallows_the_chords_only_when_rescue_is_installed(self):
        bindings = (ROOT / 'bindings.lua').read_text()
        self.assertIn(rescue.LIBDIR + '/orbit_rescue.py', bindings)
        self.assertIn('CTRL + ALT + SHIFT + ESCAPE', bindings)
        self.assertIn('SUPER + CTRL + SHIFT + B', bindings)


if __name__ == '__main__':
    unittest.main()
