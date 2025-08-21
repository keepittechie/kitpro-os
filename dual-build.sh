#!/bin/bash

set -e

#####################################################
#####################################################

BOOT_ISO="/opt/iso/Rocky-10.0-x86_64-dvd.iso"
OUTPUT_DIR="/opt/output"
WORK_DIR="$HOME/kitpro-os/repos/iso-work"
KS_DIR="$WORK_DIR/ks"
REPOS_DIR="$HOME/kitpro-os/repos"
KS_FULL="$HOME/kitpro-os/kitpro-full.ks"
KS_LIGHT="$HOME/kitpro-os/kitpro-light.ks"
ISOLINUX_CFG="$HOME/kitpro-os/isolinux/isolinux.cfg"
GRUB_CFG="$HOME/kitpro-os/EFI/BOOT/grub.cfg"
FINAL_ISO="$OUTPUT_DIR/KITproOS-10.0-dual.iso"

#####################################################
#####################################################

echo "🧹 Cleaning previous build..."
rm -rf "$WORK_DIR" "$FINAL_ISO"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR" "$KS_DIR"

#####################################################
#####################################################

echo "🌐 Downloading Kickstart files..."
curl -fsSL -o "$KS_FULL" https://repo.kitpro.us/ks/kitpro-full.ks
curl -fsSL -o "$KS_LIGHT" https://repo.kitpro.us/ks/kitpro-light.ks

#####################################################
#####################################################

echo "📂 Extracting ISO contents..."
7z x "$BOOT_ISO" -o"$WORK_DIR" >/dev/null

#####################################################
#####################################################

echo "📁 Copying local repos into ISO tree..."
mkdir -p "$WORK_DIR/BaseOS/os"
mkdir -p "$WORK_DIR/AppStream/os"
rsync -avq "$REPOS_DIR/BaseOS/os/" "$WORK_DIR/BaseOS/os/"
rsync -avq "$REPOS_DIR/AppStream/os/" "$WORK_DIR/AppStream/os/"

#####################################################
#####################################################

echo "📄 Injecting local.repo and kickstart/config files..."
mkdir -p "$WORK_DIR/etc/yum.repos.d"
cp "$KS_FULL" "$KS_DIR/kitpro-full.ks"
cp "$KS_LIGHT" "$KS_DIR/kitpro-light.ks"
cp "$ISOLINUX_CFG" "$WORK_DIR/isolinux/isolinux.cfg"
cp "$GRUB_CFG" "$WORK_DIR/EFI/BOOT/grub.cfg"

#####################################################
#####################################################

echo "📄 Correct local.repo..."
cat > "$WORK_DIR/etc/yum.repos.d/local.repo" <<EOF
[BaseOS]
name=KITpro BaseOS
baseurl=file:///run/install/repo/BaseOS/os
enabled=1
gpgcheck=0

[AppStream]
name=KITpro AppStream
baseurl=file:///run/install/repo/AppStream/os
enabled=1
gpgcheck=0
EOF

#####################################################
#####################################################

echo "📏 Work directory size:"
du -sh "$WORK_DIR"

#####################################################
#####################################################

echo "🔍 Checking for isohdpfx.bin..."
if [[ -f "$WORK_DIR/isolinux/isohdpfx.bin" ]]; then
  echo "✅ Found isohdpfx.bin"
  MBR_FLAG="-isohybrid-mbr $WORK_DIR/isolinux/isohdpfx.bin"
else
  echo "⚠️  isohdpfx.bin not found — skipping -isohybrid-mbr"
  MBR_FLAG=""
fi

#####################################################
#####################################################

echo "📦 Extracting and customizing install.img from Rocky boot ISO..."
BOOT_MNT="/mnt/rocky-boot"
sudo mkdir -p "$BOOT_MNT"
sudo mount -o loop "$BOOT_ISO" "$BOOT_MNT"

if [[ -f "$BOOT_MNT/images/install.img" ]]; then
  INSTALL_IMG="$WORK_DIR/images/install.img"
  mkdir -p "$WORK_DIR/images"
  cp "$BOOT_MNT/images/install.img" "$INSTALL_IMG"
  chmod 644 "$INSTALL_IMG"
  echo "✅ install.img copied successfully."
else
  echo "❌ install.img not found in Rocky boot ISO! Aborting."
  sudo umount "$BOOT_MNT"
  exit 1
fi

sudo umount "$BOOT_MNT"

#####################################################
#####################################################

echo "[+] Injecting custom Anaconda branding..."

INSTALL_IMG_SRC="$HOME/kitpro-os/images/install.img"
INSTALL_IMG_DEST="$WORK_DIR/images/install.img"
LOGO_SRC="$HOME/kitpro-os/branding/assets/kitpro_os.png"
TMP_DIR="$WORK_DIR/images/install-root"

# Required tools
command -v unsquashfs >/dev/null || { echo "[X] unsquashfs not found. Install squashfs-tools."; exit 1; }
command -v mksquashfs >/dev/null || { echo "[X] mksquashfs not found. Install squashfs-tools."; exit 1; }

echo "[>] Extracting install.img..."
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"
unsquashfs -no-xattrs "$INSTALL_IMG_SRC"

# Create custom branding directory
BRANDING_DIR="squashfs-root/usr/share/anaconda/branding/kitpro"
mkdir -p "$BRANDING_DIR"

# Place logo
cp "$LOGO_SRC" "$BRANDING_DIR/icon.png"

# Create branding.css
cat > "$BRANDING_DIR/branding.css" <<EOF
body {
  background-color: #0D1B2A;
}
.top-title::after {
  content: "KITpro OS 10.0 INSTALLATION";
}
EOF

# Patch os-release
OS_RELEASE="squashfs-root/etc/os-release"
sed -i 's/^NAME=.*/NAME="KITpro OS"/' "$OS_RELEASE"
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="KITpro OS 10.0"/' "$OS_RELEASE"

echo "[>] Repacking install.img..."
mksquashfs squashfs-root "$INSTALL_IMG_DEST" -noappend -comp xz -all-root >/dev/null

echo "[>] Cleaning up temp files..."
sudo rm -rf "$TMP_DIR"

echo "[✓] Anaconda branding injected successfully."

#####################################################
#####################################################

cat > "$WORK_DIR/.treeinfo" <<EOF
[header]
type = productmd.treeinfo
version = 1.2

[general]
family = KITpro OS
timestamp = $(date +%s)
version = 10.0
name = KITproOS 10.0
short = kitpro
arch = x86_64
platforms = x86_64
disc_type = dvd
discnum = 1
totaldiscs = 1
packagedir = Packages
languages = en_US
default_language = en_US
bugurl = https://repo.kitpro.us/bugs
isfinal = True
repository = BaseOS

[release]
name = KITproOS
short = kitpro
version = 10.0
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
packages = BaseOS/os/Packages
repository = BaseOS
type = variant
uid = BaseOS

[variant-AppStream]
id = AppStream
name = AppStream
packages = AppStream/os/Packages
repository = AppStream
type = variant
uid = AppStream

[base_product]
name = KITproOS
short = kitpro
version = 10.0
description = KITpro OS Custom Rocky Linux ISO
EOF

#####################################################
#####################################################

cat > "$WORK_DIR/media.repo" <<EOF
[InstallMedia]
name=KITproOS
mediaid=$(date +%s)
metadata_expire=-1
gpgcheck=0
enabled=1
baseurl=file:///run/install/repo/BaseOS/os
EOF

#####################################################
#####################################################

echo "📦 Update repos..."

createrepo_c -g "$REPOS_DIR/BaseOS/os/comps-BaseOS.xml" -x --update "$WORK_DIR/BaseOS/os"
createrepo_c -g "$REPOS_DIR/AppStream/os/comps-AppStream.xml" -x --update "$WORK_DIR/AppStream/os"

gzip -f "$WORK_DIR/BaseOS/os/repodata/"*comps-BaseOS.xml
gzip -f "$WORK_DIR/AppStream/os/repodata/"*comps-AppStream.xml

find "$WORK_DIR/BaseOS/os/repodata" -name "*comps-BaseOS.xml" -not -name "*.gz" -delete
find "$WORK_DIR/AppStream/os/repodata" -name "*comps-AppStream.xml" -not -name "*.gz" -delete

#####################################################
#####################################################

echo "🔥 Rebuilding full dual boot ISO..."
xorriso -as mkisofs \
  -r -J -joliet-long -V "KITproOS-10.0" \
  -volset "KITproOS-10.0" \
  -o "$FINAL_ISO" \
  $MBR_FLAG \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin -no-emul-boot \
  -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e images/efiboot.img -no-emul-boot \
  "$WORK_DIR"

#####################################################
#####################################################
echo "✅ Full dual boot ISO created: $FINAL_ISO"
du -sh "$FINAL_ISO"
