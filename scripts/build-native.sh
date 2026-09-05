#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! pkg-config --exists hyprland pixman-1 libdrm libinput libudev wayland-server xkbcommon; then
  echo "Orbit native bridge needs the Hyprland and Wayland development headers." >&2
  exit 1
fi

# Compare the exact ABI built from these headers, including dependency ABI
# versions. Searching fragments of optimized ELF strings can falsely pass.
expected_abi="$(hyprctl -j version | jq -er '.abiHash')"
read -r -a include_flags <<< "$(pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon)"
actual_abi="$("${CXX:-g++}" -std=c++2b "${include_flags[@]}" -E -dM "$project_dir/native/abi_probe.cpp" | awk '
  $1 == "#define" { value[$2]=$3; gsub(/"/, "", value[$2]) }
  function stripPatch(v) { sub(/\.[^.]*$/, "", v); return v }
  END {
    names[1]="GIT_COMMIT_HASH"; names[2]="AQUAMARINE_VERSION"; names[3]="HYPRUTILS_VERSION";
    names[4]="HYPRGRAPHICS_VERSION"; names[5]="HYPRCURSOR_VERSION"; names[6]="HYPRLANG_VERSION";
    for (i=1; i<=6; i++) if (!value[names[i]]) exit 1;
    printf "%s_aq_%s_hu_%s_hg_%s_hc_%s_hlg_%s\n", value[names[1]], stripPatch(value[names[2]]),
      stripPatch(value[names[3]]), stripPatch(value[names[4]]), stripPatch(value[names[5]]), stripPatch(value[names[6]]);
  }')"
if [[ -z "$expected_abi" || "$actual_abi" != "$expected_abi" ]]; then
  echo "Orbit native bridge ABI verification failed." >&2
  echo "Hyprland: ${expected_abi:-unknown}" >&2
  echo "Headers: ${actual_abi:-unknown}" >&2
  exit 1
fi

make -B -C "$project_dir/native" all

echo "Built native/orbit-drag.so for Hyprland ABI $expected_abi"
