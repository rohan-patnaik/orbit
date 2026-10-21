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

# Compiler output, scratch space and receipts stay on the real artifact mount.
# This build uses ordinary files only; no Linux image/symlink semantics required.
drive="${ORBIT_ARTIFACT_DRIVE:-/run/media/${USER}/Stuff}"
root="${ORBIT_ARTIFACT_ROOT:-$drive/Artifacts/orbit-native}"
[[ -d "$drive/Artifacts" ]] || { echo 'Orbit artifact drive unavailable.' >&2; exit 1; }
read -r mount_path mount_type mount_options < <(findmnt -rn -T "$drive" -o TARGET,FSTYPE,OPTIONS | tail -1)
[[ "$mount_path" == "$drive" && "$mount_type" != autofs && ",$mount_options," == *,rw,* ]] || {
  echo 'Orbit requires its mounted writable artifact drive; no system-drive fallback.' >&2; exit 1;
}
resolved_root="$(realpath -m "$root")"
[[ "$resolved_root" == "$drive"/Artifacts/* ]] || { echo 'Orbit artifact path escapes its drive.' >&2; exit 1; }
for confined in "$resolved_root/logs" "$resolved_root/build.lock"; do
  [[ "$(realpath -m "$confined")" == "$confined" ]] || { echo 'Orbit artifact path contains a symlink.' >&2; exit 1; }
done
source_hash="$(cat "$project_dir/native/orbit_drag.cpp" "$project_dir/native/DragTracker.hpp" \
  "$project_dir/native/XwaylandMove.hpp" "$project_dir/native/abi_probe.cpp" "${BASH_SOURCE[0]}" | sha256sum | cut -d' ' -f1)"
abi_key="$(printf '%s' "$expected_abi" | sha256sum | cut -c1-20)"
build_dir="$resolved_root/build/$abi_key/$source_hash"
[[ "$(realpath -m "$build_dir")" == "$build_dir" ]] || { echo 'Orbit build path contains a symlink.' >&2; exit 1; }
binary="$build_dir/orbit-drag.so"
receipt="$build_dir/build.json"
[[ ! -L "$binary" && ! -L "$receipt" ]] || { echo 'Orbit output contains a symlink.' >&2; exit 1; }
valid_build() {
  [[ -f "$binary" && ! -L "$binary" && -f "$receipt" && ! -L "$receipt" ]] || return 1
  local actual_sha
  actual_sha="$(sha256sum "$binary" | cut -d' ' -f1)"
  jq -e --arg sha "$actual_sha" --arg abi "$expected_abi" --arg source "$source_hash" \
    '.sha256 == $sha and .abi == $abi and .source == $source' "$receipt" >/dev/null
}
if [[ "${1:-}" == --locate ]]; then
  valid_build || exit 1
  printf '%s\n' "$binary"
  exit 0
fi
[[ $# == 0 ]] || { echo 'Usage: build-native.sh [--locate]' >&2; exit 64; }
mkdir -p "$build_dir" "$resolved_root/logs"
exec 8>"$resolved_root/build.lock"
flock 8
if valid_build; then printf '%s\n' "$binary"; exit 0; fi
free_bytes="$(df -B1 --output=avail "$build_dir" | tail -1 | tr -d ' ')"
[[ "$free_bytes" =~ ^[0-9]+$ && "$free_bytes" -ge 256000000 ]] || { echo 'Orbit needs 256 MB free for a native build.' >&2; exit 1; }
scratch="$(mktemp -d "$build_dir/tmp.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
export TMPDIR="$scratch"
"${CXX:-g++}" -O2 -shared -fPIC -std=c++2b -Wall -Wextra -Wpedantic -fno-gnu-unique \
  "${include_flags[@]}" "$project_dir/native/orbit_drag.cpp" -o "$scratch/orbit-drag.so"
sha="$(sha256sum "$scratch/orbit-drag.so" | cut -d' ' -f1)"
jq -n --arg abi "$expected_abi" --arg source "$source_hash" --arg sha "$sha" \
  '{abi:$abi,source:$source,sha256:$sha,purpose:"Orbit native bridge",status:"retained",reproducible:true}' > "$scratch/build.json"
mv -T -- "$scratch/orbit-drag.so" "$binary"
mv -T -- "$scratch/build.json" "$receipt"
printf '%s\n' "$binary"
