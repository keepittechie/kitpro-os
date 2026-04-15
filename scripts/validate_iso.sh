#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

find_iso() {
  find "$REPO_ROOT/output" -maxdepth 1 -type f -name 'KITproOS-*.iso' | sort | tail -n1
}

iso_has_path() {
  local iso_path="$1"
  local needle="$2"
  xorriso -indev "$iso_path" -find "$needle" -print 2>/dev/null | grep -Fxq "$needle"
}

extract_iso_file() {
  local iso_path="$1"
  local source_path="$2"
  local dest_path="$3"
  xorriso -osirrox on -indev "$iso_path" -extract "$source_path" "$dest_path" >/dev/null
}

ISO_PATH="${ISO_PATH:-$(find_iso)}"
[[ -n "$ISO_PATH" && -f "$ISO_PATH" ]] || { echo "No KITpro ISO found under $REPO_ROOT/output"; exit 1; }

ISO_BASENAME="$(basename "$ISO_PATH")"
EXPECTED_VERSION="${EXPECTED_VERSION:-$(sed -nE 's/^KITproOS-([0-9][0-9.]+).*/\1/p' <<<"$ISO_BASENAME")}"
EXPECTED_VOLID="${EXPECTED_VOLID:-KITproOS-${EXPECTED_VERSION:-custom}}"

REQUIRED_TREEINFO_FIELDS=("release.name" "release.short" "release.version" "base_product.short" "general.short")
REQUIRED_IMAGES=("/images/install.img" "/images/pxeboot/vmlinuz" "/images/pxeboot/initrd.img")
REQUIRED_REPO_DIRS=("/BaseOS" "/AppStream" "/BaseOS/repodata" "/AppStream/repodata")
LOGFILE="${LOGFILE:-$REPO_ROOT/iso-validate-$(date +%Y%m%d-%H%M%S).log}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

exec > >(tee -a "$LOGFILE") 2>&1

ERRORS=0

echo
echo "[->] Validating ISO: $ISO_PATH"

TREEINFO_PATH="$TMPDIR/.treeinfo"
echo
echo "[->] Validating .treeinfo..."
if ! extract_iso_file "$ISO_PATH" "/.treeinfo" "$TREEINFO_PATH"; then
  echo "[X] .treeinfo not found."
  ((ERRORS++))
else
  for FIELD in "${REQUIRED_TREEINFO_FIELDS[@]}"; do
    SECTION="${FIELD%%.*}"
    KEY="${FIELD#*.}"
    if ! awk -v section="[$SECTION]" -v key="$KEY" '
      $0 == section { in_section=1; next }
      /^\[.*\]/ { in_section=0 }
      in_section && $1 == key && $2 != "" { found=1; exit }
      END { exit !found }
    ' "$TREEINFO_PATH"; then
      echo "[X] Missing or empty: [$SECTION] $KEY"
      ((ERRORS++))
    else
      echo "[OK] [$SECTION] $KEY present"
    fi
  done
fi

echo
echo "[->] Validating image files..."
for IMG in "${REQUIRED_IMAGES[@]}"; do
  if iso_has_path "$ISO_PATH" "$IMG"; then
    echo "[OK] Found ${IMG#/}"
  else
    echo "[X] Missing file: ${IMG#/}"
    ((ERRORS++))
  fi
done

VOLUME_LABEL="$(isoinfo -d -i "$ISO_PATH" | awk -F: '/Volume id:/ {gsub(/^[ \t]+/, "", $2); print $2}')"
echo
echo "[->] Volume Label: $VOLUME_LABEL"
if [[ "$VOLUME_LABEL" != "$EXPECTED_VOLID" ]]; then
  echo "[X] Volume label mismatch (expected $EXPECTED_VOLID)"
  ((ERRORS++))
else
  echo "[OK] Volume label correct"
fi

echo
echo "[->] Validating repo directories..."
for DIR in "${REQUIRED_REPO_DIRS[@]}"; do
  if iso_has_path "$ISO_PATH" "$DIR"; then
    echo "[OK] Directory exists: ${DIR#/}"
  else
    echo "[X] Missing directory: ${DIR#/}"
    ((ERRORS++))
  fi
done

echo
echo "[->] Validation complete. Log saved to: $LOGFILE"
if [[ "$ERRORS" -eq 0 ]]; then
  echo "[OK] ISO is valid."
else
  echo "[X] ISO has $ERRORS issue(s)."
fi

exit "$ERRORS"
