#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/opt/kitpro-os"
ISO_IN="${ISO_IN:-$REPO_ROOT/iso/Rocky-10.0-x86_64-dvd.iso}"
ISO_OUT="$REPO_ROOT/output/KITproOS-10.0-$(date +%Y%m%d).iso"
KS_SRC="$REPO_ROOT/kitpro-full.flat.ks"     # <- flattened KS
KS_DST="ks/ks.cfg"                          # <- standard location
OVERLAY="$REPO_ROOT/iso-overlay"
WORK="$REPO_ROOT/.iso-work"

[[ -f "$ISO_IN" ]] || { echo "Missing $ISO_IN"; exit 1; }
[[ -f "$KS_SRC" ]] || { echo "Missing $KS_SRC (did you flatten?)"; exit 1; }
[[ -d "$OVERLAY" ]] || { echo "Missing $OVERLAY dir"; exit 1; }

# Reuse source ISO volume label to keep stage2 paths sane
VOLID="$(xorriso -indev "$ISO_IN" -pvd_info 2>/dev/null | awk -F': ' '/Volume id/ {print $2}')"
[[ -n "$VOLID" ]] || VOLID="KITPRO_OS_10"

rm -rf "$WORK"; mkdir -p "$WORK" "$(dirname "$ISO_OUT")"

echo "[1/5] Extracting base ISO..."
bsdtar -C "$WORK" -xf "$ISO_IN"

echo "[2/5] Grafting overlay + kickstart..."
rsync -a "$OVERLAY"/ "$WORK"/
install -D -m 0644 "$KS_SRC" "$WORK/$KS_DST"

echo "[3/5] Patching boot configs (inst.stage2=cdrom inst.repo=cdrom inst.ks=cdrom:/$KS_DST)..."
# ISOLINUX (BIOS)
if [[ -f "$WORK/isolinux/isolinux.cfg" ]]; then
  sed -i -E 's|(append .*)$|\1 inst.stage2=cdrom inst.repo=cdrom inst.ks=cdrom:/ks/ks.cfg|g' "$WORK/isolinux/isolinux.cfg" || true
fi
# GRUB (UEFI)
if [[ -f "$WORK/EFI/BOOT/grub.cfg" ]]; then
  sed -i -E 's|(linuxefi .*)$|\1 inst.stage2=cdrom inst.repo=cdrom inst.ks=cdrom:/ks/ks.cfg|g' "$WORK/EFI/BOOT/grub.cfg" || true
  sed -i -E 's|(linux .*)$|\1 inst.stage2=cdrom inst.repo=cdrom inst.ks=cdrom:/ks/ks.cfg|g' "$WORK/EFI/BOOT/grub.cfg" || true
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
  echo "❌ No boot media found (neither isolinux nor efiboot.img). Use the Rocky *boot* ISO as ISO_IN."
  exit 1
fi

echo "[5/5] Embedding checksum..."
implantisomd5 "$ISO_OUT" >/dev/null 2>&1 || true
echo "[✓] Built ISO: $ISO_OUT"
