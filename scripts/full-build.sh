#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

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

find_iso() {
  find "$REPO_ROOT/iso" -maxdepth 1 -type f \
    \( -name 'Rocky-*-x86_64-boot.iso' -o -name 'Rocky-*-x86_64-dvd1.iso' -o -name 'Rocky-*-x86_64-dvd.iso' \) \
    | sort | tail -n1
}

BOOT_ISO="${BOOT_ISO:-$(find_iso)}"
REPOS_DIR="${REPOS_DIR:-$REPO_ROOT/repos}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output}"
TMP_ROOT="${TMP_ROOT:-$REPO_ROOT/tmp}"
INCLUDE_SRC="${INCLUDE_SRC:-$REPO_ROOT/kickstarts/includes/xfce-wayland.ks.inc}"

[[ -n "$BOOT_ISO" && -f "$BOOT_ISO" ]] || { echo "Missing Rocky ISO under $REPO_ROOT/iso"; exit 1; }
[[ -d "$REPOS_DIR/BaseOS/os" ]] || { echo "Missing $REPOS_DIR/BaseOS/os"; exit 1; }
[[ -d "$REPOS_DIR/AppStream/os" ]] || { echo "Missing $REPOS_DIR/AppStream/os"; exit 1; }
[[ -f "$INCLUDE_SRC" ]] || { echo "Missing $INCLUDE_SRC"; exit 1; }

ISO_VERSION="${ISO_VERSION:-$(basename "$BOOT_ISO" | sed -nE 's/^Rocky-([0-9][0-9.]*)-x86_64-.*\.iso$/\1/p')}"
mkdir -p "$OUTPUT_DIR" "$TMP_ROOT"

declare -A builds=(
  ["kitpro-full"]="kitproOS-${ISO_VERSION:-custom}-full.iso"
  ["kitpro-light"]="kitproOS-${ISO_VERSION:-custom}-light.iso"
)

had_failures=0

for ks_name in "${!builds[@]}"; do
  ks_file="$REPO_ROOT/$ks_name.ks"
  output_iso="$OUTPUT_DIR/${builds[$ks_name]}"
  work_dir="$TMP_ROOT/$ks_name"
  ks_dir="$work_dir/ks"

  echo "Processing $ks_name"
  if [[ ! -f "$ks_file" ]]; then
    echo "Missing local kickstart: $ks_file"
    had_failures=1
    continue
  fi

  echo "Extracting ISO to $work_dir..."
  rm -rf "$work_dir"
  mkdir -p "$work_dir" "$ks_dir"
  extract_iso "$BOOT_ISO" "$work_dir"

  echo "Copying local repos into ISO tree..."
  mkdir -p "$work_dir/BaseOS" "$work_dir/AppStream"
  rsync -avq "$REPOS_DIR/BaseOS/os/" "$work_dir/BaseOS/"
  rsync -avq "$REPOS_DIR/AppStream/os/" "$work_dir/AppStream/"

  echo "Injecting local.repo and kickstart..."
  mkdir -p "$work_dir/etc/yum.repos.d"
  cp "$ks_file" "$ks_dir/ks.cfg"
  cp "$INCLUDE_SRC" "$ks_dir/xfce-wayland.ks.inc"
  [[ -d "$REPO_ROOT/branding" ]] && rsync -avq "$REPO_ROOT/branding/" "$work_dir/branding/"
  cat > "$work_dir/etc/yum.repos.d/local.repo" <<EOF
[BaseOS]
name=KITpro BaseOS
baseurl=file:///run/install/repo/BaseOS
enabled=1
gpgcheck=0

[AppStream]
name=KITpro AppStream
baseurl=file:///run/install/repo/AppStream
enabled=1
gpgcheck=0
EOF

  echo "Verifying repodata structure..."
  if [[ ! -f "$work_dir/BaseOS/repodata/repomd.xml" ]] || [[ ! -f "$work_dir/AppStream/repodata/repomd.xml" ]]; then
    echo "BaseOS or AppStream missing repodata"
    had_failures=1
    continue
  fi

  if [[ -f "$work_dir/isolinux/isolinux.cfg" ]]; then
    sed -i -E 's|(append .*)$|\1 inst.stage2=cdrom inst.repo=cdrom inst.ks=cdrom:/ks/ks.cfg|g' "$work_dir/isolinux/isolinux.cfg" || true
  fi
  if [[ -f "$work_dir/EFI/BOOT/grub.cfg" ]]; then
    sed -i -E 's|(linuxefi .*)$|\1 inst.stage2=cdrom inst.repo=cdrom inst.ks=cdrom:/ks/ks.cfg|g' "$work_dir/EFI/BOOT/grub.cfg" || true
    sed -i -E 's|(linux .*)$|\1 inst.stage2=cdrom inst.repo=cdrom inst.ks=cdrom:/ks/ks.cfg|g' "$work_dir/EFI/BOOT/grub.cfg" || true
  fi

  du -sh "$work_dir"

  echo "Rebuilding ISO: $output_iso"
  if xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "KITPRO_OS_${ISO_VERSION//./_}" \
    -appid "KITproOS $ks_name" \
    -publisher "KITpro Systems" \
    -J -joliet-long -r -v -T \
    -o "$output_iso" \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e images/efiboot.img \
    -no-emul-boot \
    "$work_dir"; then
    implantisomd5 "$output_iso" >/dev/null 2>&1 || true
    echo "Cleaning up: $work_dir"
    rm -rf "$work_dir"
  else
    echo "ISO build failed, keeping: $work_dir for inspection"
    had_failures=1
  fi

  echo "Finished: $output_iso"
done

exit "$had_failures"
