#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! pkg-config --exists hyprland pixman-1 libdrm libinput libudev wayland-server xkbcommon; then
  echo "Orbit native bridge needs the Hyprland and Wayland development headers." >&2
  exit 1
fi

make -C "$project_dir/native" clean all

expected_abi="$(hyprctl version | sed -n 's/^Version ABI string: //p')"
expected_commit="${expected_abi%%_*}"
commit_prefix="${expected_commit:0:32}"
commit_suffix="${expected_commit:32}"
if [[ -z "$expected_abi" || -z "$expected_commit" ]] \
  || ! strings "$project_dir/native/orbit-drag.so" | grep -F "$commit_prefix" >/dev/null \
  || ! strings "$project_dir/native/orbit-drag.so" | grep -F "$commit_suffix" >/dev/null; then
  echo "Orbit native bridge ABI verification failed." >&2
  echo "Hyprland: ${expected_abi:-unknown}" >&2
  exit 1
fi

echo "Built native/orbit-drag.so for Hyprland ABI $expected_abi"
