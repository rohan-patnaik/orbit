#!/usr/bin/env python3
"""Orbit rescue: recovery keys that work when the desktop is frozen.

Windows handles Ctrl+Alt+Del below every app, so it gets through when the
shell is wedged. This optional root service does the same below Hyprland:

  Ctrl+Alt+Shift+Esc   switch to a text-console rescue screen
  Super+Ctrl+Shift+B   restart graphics, like Win+Ctrl+Shift+B

Keyboards are only observed: events are never grabbed, stored or logged.
"""
import argparse
import fcntl
import glob
import json
import os
import select
import signal
import socket
import struct
import subprocess
import sys
import termios
import time
import tty

LIBDIR = '/usr/local/lib/orbit-rescue'
STATE_DIR = '/run/orbit-rescue'
STATE_FILE = STATE_DIR + '/session.json'
CONSOLE_UNIT = 'orbit-rescue-console.service'
RESCUE_VT = 9

EV_KEY = 1
KEY_ESC, KEY_B = 1, 48
MODIFIER_KEYS = {
    'ctrl': {29, 97},
    'shift': {42, 54},
    'alt': {56, 100},
    'super': {125, 126},
}
COMBOS = {
    'console': (frozenset({'ctrl', 'alt', 'shift'}), KEY_ESC),
    'graphics': (frozenset({'super', 'ctrl', 'shift'}), KEY_B),
}
EVENT = struct.Struct('llHHi')
# Processes whose loss ends the session rather than an app.
SESSION_CRITICAL = {
    'systemd', '(sd-pam)', 'Hyprland', 'hyprland', 'uwsm', 'dbus-daemon',
    'dbus-broker', 'dbus-broker-launch', 'pipewire', 'wireplumber',
}


def log(message):
    print(message, file=sys.stderr, flush=True)


# --- Keyboard chords -------------------------------------------------------

def held_modifiers(pressed):
    return frozenset(name for name, codes in MODIFIER_KEYS.items() if pressed & codes)


def match_combo(pressed, code):
    """The chord a key press completes; modifiers must match exactly, so
    Ctrl+Shift+Esc (Task Manager) never opens the rescue screen."""
    modifiers = held_modifiers(pressed)
    for name, (required, trigger) in COMBOS.items():
        if code == trigger and modifiers == required:
            return name
    return None


def eviocgbit(event_type, length):
    return (2 << 30) | (length << 16) | (ord('E') << 8) | (0x20 + event_type)


def is_keyboard(fd):
    bits = bytearray(96)
    try:
        fcntl.ioctl(fd, eviocgbit(EV_KEY, len(bits)), bits)
    except OSError:
        return False
    has = lambda code: bits[code // 8] >> (code % 8) & 1
    return all(has(code) for code in (KEY_ESC, KEY_B, 29, 42, 56))


class ChordWatcher:
    def __init__(self, on_combo, pattern='/dev/input/event*'):
        self.on_combo = on_combo
        self.pattern = pattern
        self.devices = {}   # fd -> path
        self.pressed = {}   # fd -> set of held key codes
        self.last_fired = {}

    def rescan(self):
        known = set(self.devices.values())
        for path in glob.glob(self.pattern):
            if path in known:
                continue
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
            except OSError:
                continue
            if is_keyboard(fd):
                self.devices[fd] = path
                self.pressed[fd] = set()
            else:
                os.close(fd)

    def drop(self, fd):
        self.devices.pop(fd, None)
        self.pressed.pop(fd, None)
        try:
            os.close(fd)
        except OSError:
            pass

    def handle(self, fd, code, value):
        held = self.pressed.setdefault(fd, set())
        if value == 0:
            held.discard(code)
            return
        if value != 1:
            return   # autorepeat
        held.add(code)
        everything = set().union(*self.pressed.values())
        combo = match_combo(everything, code)
        now = time.monotonic()
        if combo and now - self.last_fired.get(combo, -10) > 2:
            self.last_fired[combo] = now
            self.on_combo(combo)

    def read(self, fd):
        try:
            data = os.read(fd, EVENT.size * 64)
        except BlockingIOError:
            return
        except OSError:
            self.drop(fd)
            return
        for offset in range(0, len(data) - EVENT.size + 1, EVENT.size):
            _sec, _usec, kind, code, value = EVENT.unpack_from(data, offset)
            if kind == EV_KEY:
                self.handle(fd, code, value)

    def run(self, on_idle=None, idle_every=5.0):
        last_scan = last_idle = 0.0
        while True:
            now = time.monotonic()
            if now - last_scan > 3:
                self.rescan()
                last_scan = now
            if on_idle and now - last_idle > idle_every:
                on_idle()
                last_idle = now
            ready, _, _ = select.select(list(self.devices), [], [], 1.0)
            for fd in ready:
                self.read(fd)


# --- Session and compositor -------------------------------------------------

def parse_properties(text):
    values = {}
    for line in text.splitlines():
        key, sep, value = line.partition('=')
        if sep:
            values[key.strip()] = value.strip()
    return values


def run(command, timeout=3):
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None


GRAPHICAL = ('wayland', 'x11')


def session_info(session_id):
    shown = run(['loginctl', 'show-session', session_id, '-p', 'Name', '-p', 'User',
                 '-p', 'VTNr', '-p', 'LockedHint', '-p', 'Type', '-p', 'Seat'])
    if not shown or shown.returncode != 0:
        return None
    props = parse_properties(shown.stdout)
    try:
        uid = int(props.get('User', ''))
    except ValueError:
        return None
    return {
        'id': session_id,
        'user': props.get('Name', ''),
        'uid': uid,
        'vt': int(props['VTNr']) if props.get('VTNr', '').isdigit() else 0,
        'locked_hint': props.get('LockedHint') == 'yes',
        'type': props.get('Type', ''),
        'seat': props.get('Seat', ''),
    }


def seat_session_ids(listing):
    """Session IDs on seat0 from `loginctl list-sessions --no-legend`."""
    ids = []
    for line in listing.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[3] == 'seat0':
            ids.append(parts[0])
    return ids


def active_session():
    """The desktop session on seat0. Once the rescue VT is in front, logind no
    longer reports that session as active, so fall back to the seat's
    graphical session."""
    seat = run(['loginctl', 'show-seat', 'seat0', '-p', 'ActiveSession', '--value'])
    candidates = [seat.stdout.strip()] if seat and seat.returncode == 0 and seat.stdout.strip() else []
    listed = run(['loginctl', 'list-sessions', '--no-legend'])
    if listed and listed.returncode == 0:
        candidates += [sid for sid in seat_session_ids(listed.stdout) if sid not in candidates]
    for session_id in candidates:
        session = session_info(session_id)
        if session and session['type'] in GRAPHICAL:
            return session
    return None


def hyprland_sockets(uid, runtime_root='/run/user'):
    paths = glob.glob(f'{runtime_root}/{uid}/hypr/*/.socket.sock')
    return sorted(paths, key=lambda p: os.stat(p).st_mtime, reverse=True)


def hyprland_request(uid, request, timeout=2.0):
    """Ask the compositor directly over its socket; None when it can't answer."""
    for path in hyprland_sockets(uid):
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                sock.settimeout(timeout)
                sock.connect(path)
                sock.sendall(request.encode())
                chunks = []
                while True:
                    chunk = sock.recv(65536)
                    if not chunk:
                        break
                    chunks.append(chunk)
                return b''.join(chunks).decode(errors='replace')
        except OSError:
            continue
    return None


def lock_state(monitors_json):
    """Mirror omarchy-hyprland-session-locked: True locked, False unlocked,
    None undetermined."""
    try:
        monitors = json.loads(monitors_json)
    except (TypeError, ValueError):
        return None
    blockers = [m.get('solitaryBlockedBy') or [] for m in monitors if isinstance(m, dict)]
    if any('LOCK' in b for b in blockers):
        return True
    if any('WORKSPACE' not in b for b in blockers):
        return False
    return None


def probe_session():
    session = active_session()
    if not session:
        return None
    monitors = hyprland_request(session['uid'], 'j/monitors')
    session['responding'] = monitors is not None
    state = lock_state(monitors) if monitors is not None else None
    session['locked'] = True if session['locked_hint'] else state
    return session


def remember(session, path=STATE_FILE):
    if not session or session.get('locked') is None:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temporary = path + '.tmp'
    with open(temporary, 'w') as handle:
        json.dump({'id': session['id'], 'locked': session['locked'], 'at': time.time()}, handle)
    os.replace(temporary, path)


def effective_lock(session, path=STATE_FILE):
    """While the compositor is frozen, trust the last state it reported for
    this session. With nothing known, fail closed."""
    if session.get('locked') is not None:
        return session['locked']
    try:
        with open(path) as handle:
            saved = json.load(handle)
        if saved.get('id') == session['id']:
            return bool(saved.get('locked'))
    except (OSError, ValueError):
        pass
    return True


# --- Graphics ---------------------------------------------------------------

def display_gpu(drm_root='/sys/class/drm'):
    """PCI address of the GPU driving a connected display."""
    for status in sorted(glob.glob(f'{drm_root}/card*-*/status')):
        try:
            with open(status) as handle:
                if handle.read().strip() != 'connected':
                    continue
        except OSError:
            continue
        card = os.path.basename(os.path.dirname(status)).split('-', 1)[0]
        device = os.path.realpath(f'{drm_root}/{card}/device')
        return os.path.basename(device)
    return None


def gpu_recover_file(pci, debug_root='/sys/kernel/debug/dri'):
    for name_file in sorted(glob.glob(f'{debug_root}/*/name')):
        directory = os.path.dirname(name_file)
        if not os.path.basename(directory).isdigit():
            continue
        try:
            with open(name_file) as handle:
                name = handle.read()
        except OSError:
            continue
        if name.startswith('amdgpu ') and f'dev={pci}' in name:
            recover = os.path.join(directory, 'amdgpu_gpu_recover')
            if os.path.exists(recover):
                return recover
    return None


def reset_gpu():
    pci = display_gpu()
    if not pci:
        return False, 'No connected display found.'
    recover = gpu_recover_file(pci)
    if not recover:
        return False, f'GPU {pci} has no reset control (only AMD GPUs are supported).'
    try:
        with open(recover) as handle:
            handle.read()
    except OSError as error:
        return False, f'GPU reset failed: {error.strerror or error}'
    return True, f'Reset GPU {pci}.'


def restart_graphics(session=None):
    """A live compositor only needs its renderer rebuilt; a frozen one gets
    the driver-level GPU reset, as Windows' TDR would."""
    session = session or active_session()
    if session and hyprland_request(session['uid'], 'version') is not None:
        reply = hyprland_request(session['uid'], 'eval hl.dispatch(hl.dsp.force_renderer_reload())')
        if reply is not None and 'error' not in reply.lower():
            return True, 'Reloaded the desktop renderer.'
    return reset_gpu()


# --- Processes --------------------------------------------------------------

def process_rows(uid, proc='/proc'):
    rows = {}
    for entry in os.listdir(proc):
        if not entry.isdigit():
            continue
        base = f'{proc}/{entry}'
        try:
            if os.stat(base).st_uid != uid:
                continue
            with open(base + '/stat') as handle:
                stat = handle.read()
            with open(base + '/comm') as handle:
                name = handle.read().strip()
        except OSError:
            continue
        fields = stat[stat.rfind(')') + 2:].split()
        if len(fields) < 22:
            continue
        rows[int(entry)] = {
            'pid': int(entry), 'name': name,
            'ticks': int(fields[11]) + int(fields[12]),
            'rss': int(fields[21]) * os.sysconf('SC_PAGE_SIZE'),
        }
    return rows


def top_processes(uid, limit=12, sample=0.5, proc='/proc'):
    before = process_rows(uid, proc)
    time.sleep(sample)
    after = process_rows(uid, proc)
    hz = os.sysconf('SC_CLK_TCK')
    rows = []
    for pid, row in after.items():
        if row['name'] in SESSION_CRITICAL:
            continue
        previous = before.get(pid)
        delta = row['ticks'] - previous['ticks'] if previous else 0
        rows.append({**row, 'cpu': 100.0 * delta / hz / sample})
    rows.sort(key=lambda r: (r['cpu'], r['rss']), reverse=True)
    return rows[:limit]


def end_process(pid, uid, force=False, proc='/proc'):
    """Signal only the session user's own process, re-checked just before."""
    try:
        if os.stat(f'{proc}/{pid}').st_uid != uid:
            return False
        os.kill(pid, signal.SIGKILL if force else signal.SIGTERM)
        return True
    except OSError:
        return False


def alive(pid, proc='/proc'):
    try:
        with open(f'{proc}/{pid}/stat') as handle:
            return handle.read().rsplit(')', 1)[1].split()[0] != 'Z'
    except (OSError, IndexError):
        return False


# --- Console ----------------------------------------------------------------

VT_ACTIVATE, VT_WAITACTIVE = 0x5606, 0x5607


def switch_vt(number):
    if not number:
        return
    try:
        fd = os.open('/dev/tty0', os.O_RDWR | os.O_NOCTTY)
        try:
            fcntl.ioctl(fd, VT_ACTIVATE, number)
            fcntl.ioctl(fd, VT_WAITACTIVE, number)
        finally:
            os.close(fd)
    except OSError as error:
        log(f'Could not switch to VT {number}: {error}')


def human_size(size):
    for unit in ('B', 'KiB', 'MiB', 'GiB'):
        if size < 1024 or unit == 'GiB':
            return f'{size:.0f} {unit}' if unit == 'B' else f'{size:.1f} {unit}'
        size /= 1024


def menu_items(locked):
    items = [('1', 'Return to desktop', 'return')]
    if not locked:
        items.append(('2', 'End a task', 'tasks'))
    items.append(('3', 'Restart graphics', 'graphics'))
    if not locked:
        items.append(('4', 'Sign out (restarts the desktop, unsaved work is lost)', 'signout'))
    items.append(('5', 'Restart computer', 'reboot'))
    return items


class Console:
    def __init__(self):
        self.session = probe_session() or {}
        self.locked = effective_lock(self.session) if self.session else True

    def key(self):
        data = os.read(0, 8)
        if data in (b'\x1b', b'\x03'):
            return 'esc'
        return data[:1].decode(errors='ignore').lower()

    def write(self, text=''):
        sys.stdout.write(text + '\r\n')

    def screen(self, title):
        sys.stdout.write('\x1b[2J\x1b[H')
        host = os.uname().nodename
        self.write(f'  Orbit rescue  ·  {host}  ·  {time.strftime("%H:%M")}')
        self.write(f'  {title}')
        self.write()

    def confirm(self, question):
        self.write(f'  {question} [y/N]')
        sys.stdout.flush()
        return self.key() == 'y'

    def pause(self, message):
        self.write()
        self.write(f'  {message}')
        self.write('  Press any key.')
        sys.stdout.flush()
        self.key()

    def status(self):
        if not self.session:
            return 'No desktop session found.'
        compositor = 'responding' if self.session.get('responding') else 'NOT responding'
        lock = '  ·  locked' if self.locked else ''
        return f'Desktop of {self.session["user"]}: {compositor}{lock}'

    def tasks(self):
        while True:
            self.screen('End a task')
            self.write('  Measuring…')
            sys.stdout.flush()
            rows = top_processes(self.session['uid'])
            self.screen('End a task  ·  busiest first')
            self.write(f'      {"Name":<18}{"PID":>8}{"CPU":>8}{"Memory":>12}')
            letters = 'abcdefghijkl'
            for letter, row in zip(letters, rows):
                self.write(f'  {letter}   {row["name"][:17]:<18}{row["pid"]:>8}'
                           f'{row["cpu"]:>7.0f}%{human_size(row["rss"]):>12}')
            self.write()
            self.write('  Choose a letter to end that task, r to refresh, Esc to go back.')
            sys.stdout.flush()
            choice = self.key()
            if choice == 'esc':
                return
            if choice == 'r' or choice not in letters[:len(rows)]:
                continue
            row = rows[letters.index(choice)]
            if not self.confirm(f'End {row["name"]} ({row["pid"]})?'):
                continue
            end_process(row['pid'], self.session['uid'])
            deadline = time.monotonic() + 3
            while alive(row['pid']) and time.monotonic() < deadline:
                time.sleep(0.2)
            if alive(row['pid']) and self.confirm(f'{row["name"]} is still running. Force it to end?'):
                end_process(row['pid'], self.session['uid'], force=True)

    def run(self):
        while True:
            self.screen(self.status())
            items = menu_items(self.locked)
            for number, label, _action in items:
                self.write(f'  {number}  {label}')
            self.write()
            self.write('  Press a number. Esc returns to the desktop.')
            sys.stdout.flush()
            choice = self.key()
            action = 'return' if choice == 'esc' else {n: a for n, _, a in items}.get(choice)
            if action == 'return':
                return
            if action == 'tasks':
                self.tasks()
            elif action == 'graphics':
                self.screen('Restarting graphics…')
                sys.stdout.flush()
                switch_vt(self.session.get('vt'))
                ok, message = restart_graphics(self.session or None)
                log(message)
                return
            elif action == 'signout' and self.confirm('Sign out now? Unsaved work in every app is lost.'):
                run(['loginctl', 'terminate-session', self.session['id']])
                return
            elif action == 'reboot' and self.confirm('Restart the computer now?'):
                run(['systemctl', 'reboot'])
                return


def console_main():
    # Read the desktop's state while it is still the seat's active session.
    console = Console()
    session = console.session
    switch_vt(RESCUE_VT)
    try:
        attributes = termios.tcgetattr(0)
    except termios.error:
        attributes = None
    try:
        if attributes is not None:
            tty.setcbreak(0)
        console.run()
    finally:
        if attributes is not None:
            termios.tcsetattr(0, termios.TCSAFLUSH, attributes)
        sys.stdout.write('\x1b[2J\x1b[H')
        sys.stdout.flush()
        switch_vt((session or {}).get('vt') or 1)


# --- Daemon -----------------------------------------------------------------

def daemon_main():
    def on_combo(combo):
        log(f'Rescue chord: {combo}')
        if combo == 'console':
            subprocess.Popen(['systemctl', 'start', '--no-block', CONSOLE_UNIT])
        elif combo == 'graphics':
            subprocess.Popen([sys.executable, '-I', os.path.abspath(__file__), 'restart-graphics'])

    def on_idle():
        try:
            remember(probe_session())
        except OSError as error:
            log(f'Session check failed: {error}')

    signal.signal(signal.SIGCHLD, signal.SIG_IGN)
    ChordWatcher(on_combo).run(on_idle=on_idle)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('command', choices=['daemon', 'console', 'restart-graphics', 'status'])
    args = parser.parse_args(argv)
    if args.command == 'daemon':
        daemon_main()
    elif args.command == 'console':
        console_main()
    elif args.command == 'restart-graphics':
        ok, message = restart_graphics()
        log(message)
        return 0 if ok else 1
    else:
        session = probe_session()
        print(json.dumps({'session': session, 'gpu': display_gpu(),
                          'gpuReset': bool(gpu_recover_file(display_gpu() or ''))}, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
