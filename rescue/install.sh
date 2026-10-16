#!/bin/bash
# Install or remove Orbit's optional rescue keys. Needs root:
#   sudo ./rescue/install.sh            install and start
#   sudo ./rescue/install.sh --remove   stop and remove
set -euo pipefail

LIBDIR=/usr/local/lib/orbit-rescue
UNITDIR=/etc/systemd/system
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: the rescue keys are read below the desktop, as root." >&2
  exit 1
fi

if [[ ${1:-} == --remove ]]; then
  systemctl disable --now orbit-rescued.service 2>/dev/null || true
  systemctl stop orbit-rescue-console.service 2>/dev/null || true
  rm -f "$UNITDIR/orbit-rescued.service" "$UNITDIR/orbit-rescue-console.service"
  rm -rf "$LIBDIR"
  systemctl daemon-reload
  echo "Orbit rescue keys removed."
  exit 0
fi

install -Dm644 "$HERE/orbit_rescue.py" "$LIBDIR/orbit_rescue.py"
install -Dm644 "$HERE/orbit-rescued.service" "$UNITDIR/orbit-rescued.service"
install -Dm644 "$HERE/orbit-rescue-console.service" "$UNITDIR/orbit-rescue-console.service"
systemctl daemon-reload
systemctl enable orbit-rescued.service >/dev/null
systemctl restart orbit-rescued.service
echo "Orbit rescue keys installed:"
echo "  Ctrl+Alt+Shift+Esc   rescue screen"
echo "  Super+Ctrl+Shift+B   restart graphics"
