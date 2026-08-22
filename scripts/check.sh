#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

omarchy plugin validate "$project_dir"
node --test "$project_dir"/tests/*.test.cjs

mapfile -t qml_files < <(find "$project_dir" -type f -name '*.qml' -not -path '*/.git/*' | sort)
if ((${#qml_files[@]} > 0)); then
  /usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell "${qml_files[@]}"
  for qml_file in "${qml_files[@]}"; do
    formatted_file="$(mktemp)"
    /usr/lib/qt6/bin/qmlformat -w 2 --semicolon-rule essential "$qml_file" > "$formatted_file"
    if ! cmp -s "$qml_file" "$formatted_file"; then
      diff -u "$qml_file" "$formatted_file" || true
      rm -f "$formatted_file"
      echo "QML formatting check failed: $qml_file" >&2
      exit 1
    fi
    rm -f "$formatted_file"
  done
fi

git -C "$project_dir" diff --check
