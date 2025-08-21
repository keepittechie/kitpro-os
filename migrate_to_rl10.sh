#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$PWD}"

echo "[i] Using repo root: $ROOT"

# 1) Update Kickstarts version header
for ks in "$ROOT"/*.ks "$ROOT"/kickstarts/*.ks; do
  [[ -f "$ks" ]] || continue
  echo "[*] Patching $ks"
  sed -i 's/^#version=ROCKY9/#version=ROCKY10/' "$ks"
  # Replace obvious 9.x mentions in comments
  sed -i 's/Rocky Linux 9/Rocky Linux 10/g' "$ks" || true
done

# 2) Update dual-build & helper scripts ISO paths + labels
for f in "$ROOT"/dual-build.sh "$ROOT"/scripts/full-build.sh "$ROOT"/scripts/validate_iso.sh; do
  [[ -f "$f" ]] || continue
  echo "[*] Patching $f"
  sed -i 's/Rocky-9\.5-x86_64-dvd\.iso/Rocky-10.0-x86_64-dvd.iso/g' "$f"
  sed -i 's/KITproOS-9\.5/KITproOS-10.0/g' "$f"
  # Bump remaining 9.5 strings conservatively
  sed -i 's/9\.5/10.0/g' "$f"
done

# 3) Update repos mirrorlist if present
if [[ -f "$ROOT/repos/mirrorlist" ]]; then
  echo "[*] Patching repos/mirrorlist"
  sed -i 's#/9\.5/#/10.0/#g' "$ROOT/repos/mirrorlist"
fi

echo
echo "[!] NOTE: Custom RPMs in branding/packages are built for el9:"
echo "    $(ls -1 "$ROOT"/branding/packages 2>/dev/null | grep -E '\.el9\.' || true)"
echo "    You must rebuild/sign el10 packages and update kickstarts to use them."
echo
echo "[✓] Basic text substitutions done."
