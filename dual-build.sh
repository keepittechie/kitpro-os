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
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output}"
WORK_DIR="${WORK_DIR:-$REPO_ROOT/work/iso-dual}"
KS_DIR="$WORK_DIR/ks"
REPOS_DIR="${REPOS_DIR:-$REPO_ROOT/repos}"
COMPS_DIR="${COMPS_DIR:-$REPO_ROOT/comps}"
KS_FULL="${KS_FULL:-$REPO_ROOT/kitpro-full.ks}"
KS_LIGHT="${KS_LIGHT:-$REPO_ROOT/kitpro-light.ks}"
ISOLINUX_CFG="${ISOLINUX_CFG:-$REPO_ROOT/isolinux/isolinux.cfg}"
GRUB_CFG="${GRUB_CFG:-$REPO_ROOT/EFI/BOOT/grub.cfg}"
FINAL_ISO="${FINAL_ISO:-$OUTPUT_DIR/KITproOS-${ISO_VERSION:-custom}-dual.iso}"

[[ -f "$KS_FULL" ]] || { echo "Missing $KS_FULL"; exit 1; }
[[ -f "$KS_LIGHT" ]] || { echo "Missing $KS_LIGHT"; exit 1; }
[[ -d "$REPOS_DIR/BaseOS/os" ]] || { echo "Missing $REPOS_DIR/BaseOS/os"; exit 1; }
[[ -d "$REPOS_DIR/AppStream/os" ]] || { echo "Missing $REPOS_DIR/AppStream/os"; exit 1; }
[[ -f "$COMPS_DIR/comps-BaseOS.xml" ]] || { echo "Missing $COMPS_DIR/comps-BaseOS.xml"; exit 1; }
[[ -f "$COMPS_DIR/comps-AppStream.xml" ]] || { echo "Missing $COMPS_DIR/comps-AppStream.xml"; exit 1; }
INCLUDE_SRC="${INCLUDE_SRC:-$REPO_ROOT/kickstarts/includes/xfce-wayland.ks.inc}"
[[ -f "$INCLUDE_SRC" ]] || { echo "Missing $INCLUDE_SRC"; exit 1; }
command -v createrepo_c >/dev/null 2>&1 || { echo "createrepo_c not found"; exit 1; }
command -v unsquashfs >/dev/null 2>&1 || { echo "unsquashfs not found"; exit 1; }
command -v mksquashfs >/dev/null 2>&1 || { echo "mksquashfs not found"; exit 1; }

echo "Cleaning previous build..."
rm -rf "$WORK_DIR" "$FINAL_ISO"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR" "$KS_DIR"

echo "Extracting ISO contents..."
extract_iso "$ISO_IN" "$WORK_DIR"

echo "Copying local repos into ISO tree..."
mkdir -p "$WORK_DIR/BaseOS" "$WORK_DIR/AppStream"
rsync -avq "$REPOS_DIR/BaseOS/os/" "$WORK_DIR/BaseOS/"
rsync -avq "$REPOS_DIR/AppStream/os/" "$WORK_DIR/AppStream/"

echo "Injecting local.repo and kickstart/config files..."
mkdir -p "$WORK_DIR/etc/yum.repos.d"
cp "$KS_FULL" "$KS_DIR/kitpro-full.ks"
cp "$KS_LIGHT" "$KS_DIR/kitpro-light.ks"
cp "$INCLUDE_SRC" "$KS_DIR/xfce-wayland.ks.inc"
[[ -d "$REPO_ROOT/branding" ]] && rsync -avq "$REPO_ROOT/branding/" "$WORK_DIR/branding/"
[[ -f "$ISOLINUX_CFG" && -d "$WORK_DIR/isolinux" ]] && cp "$ISOLINUX_CFG" "$WORK_DIR/isolinux/isolinux.cfg"
[[ -f "$GRUB_CFG" && -d "$WORK_DIR/EFI/BOOT" ]] && cp "$GRUB_CFG" "$WORK_DIR/EFI/BOOT/grub.cfg"

cat > "$WORK_DIR/etc/yum.repos.d/local.repo" <<EOF
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

echo "Work directory size:"
du -sh "$WORK_DIR"

MBR_ARGS=()
if [[ -f "$WORK_DIR/isolinux/isohdpfx.bin" ]]; then
  echo "Found isohdpfx.bin"
  MBR_ARGS=(-isohybrid-mbr "$WORK_DIR/isolinux/isohdpfx.bin")
else
  echo "isohdpfx.bin not found; skipping -isohybrid-mbr"
fi

echo "Extracting and customizing install.img..."
INSTALL_IMG_DEST="$WORK_DIR/images/install.img"
mkdir -p "$WORK_DIR/images"
xorriso -osirrox on -indev "$ISO_IN" -extract /images/install.img "$INSTALL_IMG_DEST" >/dev/null

LOGO_SRC="$REPO_ROOT/branding/assets/kitpro_os.png"
TMP_DIR="$WORK_DIR/images/install-root"
[[ -f "$LOGO_SRC" ]] || { echo "Missing $LOGO_SRC"; exit 1; }

mkdir -p "$TMP_DIR"
(
  cd "$TMP_DIR"
  unsquashfs -no-xattrs "$INSTALL_IMG_DEST" >/dev/null
)

BRANDING_DIR="$TMP_DIR/squashfs-root/usr/share/anaconda/branding/kitpro"
mkdir -p "$BRANDING_DIR"
cp "$LOGO_SRC" "$BRANDING_DIR/icon.png"

cat > "$BRANDING_DIR/branding.css" <<EOF
body {
  background-color: #0D1B2A;
}
.top-title::after {
  content: "KITpro OS ${ISO_VERSION:-Custom} INSTALLATION";
}
EOF

OS_RELEASE="$TMP_DIR/squashfs-root/etc/os-release"
sed -i 's/^NAME=.*/NAME="KITpro OS"/' "$OS_RELEASE"
sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"KITpro OS ${ISO_VERSION:-Custom}\"/" "$OS_RELEASE"

echo "Repacking install.img..."
mksquashfs "$TMP_DIR/squashfs-root" "$INSTALL_IMG_DEST" -noappend -comp xz -all-root >/dev/null
rm -rf "$TMP_DIR"

cat > "$WORK_DIR/.treeinfo" <<EOF
[header]
type = productmd.treeinfo
version = 1.2

[general]
family = KITpro OS
timestamp = $(date +%s)
version = ${ISO_VERSION:-custom}
name = KITproOS ${ISO_VERSION:-Custom}
short = kitpro
arch = x86_64
platforms = x86_64
disc_type = dvd
discnum = 1
totaldiscs = 1
packagedir = AppStream/Packages
languages = en_US
default_language = en_US
bugurl = https://repo.kitpro.us/bugs
isfinal = True
repository = AppStream
variant = AppStream

[release]
name = KITproOS
short = kitpro
version = ${ISO_VERSION:-custom}
is_layered = false

[images-x86_64]
kernel = images/pxeboot/vmlinuz
initrd = images/pxeboot/initrd.img
efiboot.img = images/efiboot.img

[stage2]
mainimage = images/install.img

[tree]
arch = x86_64
build_timestamp = $(date +%s)
platforms = x86_64
variants = BaseOS,AppStream

[variant-BaseOS]
id = BaseOS
name = BaseOS
packages = BaseOS/Packages
repository = BaseOS
type = variant
uid = BaseOS

[variant-AppStream]
id = AppStream
name = AppStream
packages = AppStream/Packages
repository = AppStream
type = variant
uid = AppStream

[base_product]
name = KITproOS
short = kitpro
version = ${ISO_VERSION:-custom}
description = KITpro OS Custom Rocky Linux ISO
EOF

cat > "$WORK_DIR/media.repo" <<EOF
[InstallMedia]
name=KITproOS
mediaid=$(date +%s)
metadata_expire=-1
gpgcheck=0
cost=500
EOF

echo "Updating repo metadata..."
createrepo_c -g "$COMPS_DIR/comps-BaseOS.xml" --update "$WORK_DIR/BaseOS"
createrepo_c -g "$COMPS_DIR/comps-AppStream.xml" --update "$WORK_DIR/AppStream"

echo "Rebuilding full dual boot ISO..."
xorriso -as mkisofs \
  -r -J -joliet-long \
  -V "KITproOS-${ISO_VERSION:-custom}" \
  -volset "KITproOS-${ISO_VERSION:-custom}" \
  -o "$FINAL_ISO" \
  "${MBR_ARGS[@]}" \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin -no-emul-boot \
  -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e images/efiboot.img -no-emul-boot \
  "$WORK_DIR"

implantisomd5 "$FINAL_ISO" >/dev/null 2>&1 || true
echo "Full dual boot ISO created: $FINAL_ISO"
du -sh "$FINAL_ISO"
