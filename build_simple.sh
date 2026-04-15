#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$SCRIPT_DIR}"

find_iso() {
  find "$REPO_ROOT/iso" -maxdepth 1 -type f \
    \( -name 'Rocky-*-x86_64-dvd1.iso' -o -name 'Rocky-*-x86_64-dvd.iso' \) \
    | sort | tail -n1
}

ISO_IN="${ISO_IN:-$(find_iso)}"
ISO_VERSION="${ISO_VERSION:-$(basename "$ISO_IN" | sed -nE 's/^Rocky-([0-9][0-9.]*)-x86_64-.*\.iso$/\1/p')}"
KS="${KS:-$REPO_ROOT/kitpro-light.ks}"
OUT="${OUT:-$REPO_ROOT/output/KITproOS-${ISO_VERSION:-custom}-$(date +%Y%m%d).iso}"

[[ -n "$ISO_IN" && -f "$ISO_IN" ]] || { echo "Missing Rocky ISO under $REPO_ROOT/iso"; exit 1; }
[[ -f "$KS" ]] || { echo "Missing $KS"; exit 1; }

mkdir -p "$(dirname "$OUT")"

cmd=(
  mkksiso
  --ks "$KS"
)

[[ -d "$REPO_ROOT/iso-overlay/etc" ]] && cmd+=(-a "$REPO_ROOT/iso-overlay/etc")
[[ -d "$REPO_ROOT/iso-overlay/usr" ]] && cmd+=(-a "$REPO_ROOT/iso-overlay/usr")
[[ -d "$REPO_ROOT/branding" ]] && cmd+=(-a "$REPO_ROOT/branding")

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  if sudo -n true >/dev/null 2>&1; then
    cmd=(sudo "${cmd[@]}")
  else
    echo "Running without root; passing --skip-mkefiboot." >&2
    cmd+=(--skip-mkefiboot)
  fi
fi

cmd+=("$ISO_IN" "$OUT")

"${cmd[@]}"
echo "Built ISO: $OUT"
