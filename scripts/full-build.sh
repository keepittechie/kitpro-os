#!/bin/bash

REPO_BASE="https://repo.kitpro.us/ks"
BOOT_ISO="$HOME/kitpro-os/iso/Rocky-9.5-x86_64-boot.iso"
REPOS_DIR="$HOME/kitpro-os/repos"
LOCAL_REPO_FILE="$REPOS_DIR/local.repo"
OUTPUT_DIR="/opt/output"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

declare -A builds=(
  ["kitpro-full"]="kitproOS-9.5-full.iso"
  ["kitpro-light"]="kitproOS-9.5-light.iso"
)

for ks_name in "${!builds[@]}"; do
  ks_url="$REPO_BASE/$ks_name.ks"
  ks_file="$HOME/kitpro-os/$ks_name.ks"
  output_iso="$OUTPUT_DIR/${builds[$ks_name]}"
  work_dir="$HOME/kitpro-os/tmp/$ks_name"

  echo "🔧 Processing $ks_name"
  echo "🌐 Downloading kickstart: $ks_url"
  curl -fsSL -o "$ks_file" "$ks_url" || {
    echo "❌ Failed to download $ks_url"
    continue
  }

  echo "📦 Extracting ISO to $work_dir..."
  rm -rf "$work_dir"
  mkdir -p "$work_dir"
  bsdtar -C "$work_dir" -xf "$BOOT_ISO"

  echo "📁 Copying local repos into ISO tree..."
  cp -r "$REPOS_DIR/BaseOS" "$work_dir/"
  cp -r "$REPOS_DIR/AppStream" "$work_dir/"

  echo "📄 Injecting local.repo into ISO..."
  mkdir -p "$work_dir/etc/yum.repos.d"
  cp "$LOCAL_REPO_FILE" "$work_dir/etc/yum.repos.d/local.repo"

  echo "🧪 Verifying repodata structure..."
  if [[ ! -f "$work_dir/BaseOS/repodata/repomd.xml" ]] || [[ ! -f "$work_dir/AppStream/repodata/repomd.xml" ]]; then
    echo "❌ BaseOS or AppStream missing repodata"
    continue
  fi

  du -sh "$work_dir"

  echo "🔥 Rebuilding ISO: $output_iso"
  xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "KITPRO_OS" \
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
    "$work_dir"

  if [[ $? -eq 0 ]]; then
    echo "🧹 Cleaning up: $work_dir"
    rm -rf "$work_dir"
  else
    echo "⚠️ ISO build failed, keeping: $work_dir for inspection"
  fi

  echo "✅ Finished: $output_iso"
done
