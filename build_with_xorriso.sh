#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$SCRIPT_DIR}"

find_iso() {
  find "$REPO_ROOT/iso" -maxdepth 1 -type f \
    \( -name 'Rocky-*-x86_64-dvd1.iso' -o -name 'Rocky-*-x86_64-dvd.iso' \) \
    | sort | tail -n1
}

extract_iso() {
  local iso_path="$1"
  local dest_dir="$2"

  if command -v bsdtar >/dev/null 2>&1; then
    bsdtar -C "$dest_dir" -xf "$iso_path"
  elif command -v 7z >/dev/null 2>&1; then
    7z x -y "-o$dest_dir" "$iso_path" >/dev/null
  else
    xorriso -osirrox on -indev "$iso_path" -extract / "$dest_dir" >/dev/null
  fi
}

ISO_IN="${ISO_IN:-$(find_iso)}"
[[ -n "$ISO_IN" && -f "$ISO_IN" ]] || { echo "Missing Rocky ISO under $REPO_ROOT/iso"; exit 1; }

ISO_VERSION="${ISO_VERSION:-$(basename "$ISO_IN" | sed -nE 's/^Rocky-([0-9][0-9.]*)-x86_64-.*\.iso$/\1/p')}"
ISO_OUT="${ISO_OUT:-$REPO_ROOT/output/KITproOS-${ISO_VERSION:-custom}-$(date +%Y%m%d).iso}"
KS_SRC="${KS_SRC:-$REPO_ROOT/kitpro-light.ks}"
KS_DST="ks/ks.cfg"
OVERLAY="${OVERLAY:-$REPO_ROOT/iso-overlay}"
WORK="${WORK:-$REPO_ROOT/.iso-work}"

[[ -f "$KS_SRC" ]] || { echo "Missing $KS_SRC"; exit 1; }
[[ -d "$OVERLAY" ]] || { echo "Missing $OVERLAY dir"; exit 1; }

VOLID="$(xorriso -indev "$ISO_IN" -pvd_info 2>/dev/null | awk -F': ' '/Volume [Ii]d/ {print $2}')"
[[ -n "$VOLID" ]] || VOLID="KITPRO_OS_${ISO_VERSION//./_}"

rm -rf "$WORK"
mkdir -p "$WORK" "$(dirname "$ISO_OUT")"

echo "[1/5] Extracting base ISO..."
extract_iso "$ISO_IN" "$WORK"

echo "[2/5] Grafting overlay + kickstart..."
rsync -a "$OVERLAY"/ "$WORK"/
install -D -m 0644 "$KS_SRC" "$WORK/$KS_DST"
[[ -d "$REPO_ROOT/branding" ]] && rsync -a "$REPO_ROOT/branding"/ "$WORK/branding"/

echo "[3/5] Patching boot configs (inst.stage2=cdrom inst.repo=cdrom inst.ks=cdrom:/$KS_DST)..."
if [[ -f "$WORK/isolinux/isolinux.cfg" ]]; then
  sed -i -E 's|^([[:space:]]*append .*)$|\1 inst.stage2=cdrom inst.repo=cdrom inst.ks=cdrom:/ks/ks.cfg|g' "$WORK/isolinux/isolinux.cfg" || true
fi
if [[ -f "$WORK/EFI/BOOT/grub.cfg" ]]; then
  sed -i -E 's|^([[:space:]]*linuxefi .*)$|\1 inst.stage2=cdrom inst.repo=cdrom inst.ks=cdrom:/ks/ks.cfg|g' "$WORK/EFI/BOOT/grub.cfg" || true
  sed -i -E 's|^([[:space:]]*linux .*)$|\1 inst.stage2=cdrom inst.repo=cdrom inst.ks=cdrom:/ks/ks.cfg|g' "$WORK/EFI/BOOT/grub.cfg" || true
fi

echo "[4/5] Rebuilding ISO (auto-detect BIOS/UEFI boot media)..."
BIOS_BIN="isolinux/isolinux.bin"
BIOS_CAT="isolinux/boot.cat"
UEFI_IMG="images/efiboot.img"

if [[ -f "$WORK/$BIOS_BIN" && -f "$WORK/$UEFI_IMG" ]]; then
  echo "  -> BIOS + UEFI"
  xorriso -as mkisofs \
    -iso-level 3 -full-iso9660-filenames \
    -volid "$VOLID" -appid "KITproOS" -publisher "KITpro Systems" \
    -J -joliet-long -r -T \
    -o "$ISO_OUT" \
    -b "$BIOS_BIN" -c "$BIOS_CAT" \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e "$UEFI_IMG" -no-emul-boot \
    "$WORK"
elif [[ -f "$WORK/$UEFI_IMG" ]]; then
  echo "  -> UEFI-only (no isolinux on source ISO)"
  xorriso -as mkisofs \
    -iso-level 3 -full-iso9660-filenames \
    -volid "$VOLID" -appid "KITproOS" -publisher "KITpro Systems" \
    -J -joliet-long -r -T \
    -o "$ISO_OUT" \
    -eltorito-boot "$UEFI_IMG" \
    -no-emul-boot \
    "$WORK"
else
  echo "No boot media found (neither isolinux nor efiboot.img)."
  exit 1
fi

echo "[5/5] Embedding checksum..."
implantisomd5 "$ISO_OUT" >/dev/null 2>&1 || true
echo "[✓] Built ISO: $ISO_OUT"
