#!/bin/bash
set -e

# === Configuration ===
REPO_DIR="$HOME/kitpro-os/repos"
COMPS_DIR="$HOME/kitpro-os/comps"
BASEOS_PATH="$REPO_DIR/BaseOS/os"
APPSTREAM_PATH="$REPO_DIR/AppStream/os"
ARCH="x86_64"
LOGFILE="$HOME/kitpro-os/repo-diff-$(date +%Y%m%d-%H%M%S).log"

# === Setup ===
echo "[i] Checking for required tools..." | tee -a "$LOGFILE"

for tool in dnf-utils createrepo_c rpm; do
  if ! command -v "${tool%%-*}" &> /dev/null; then
    echo "[!]  $tool is missing. You may need to run: sudo dnf install -y dnf-utils createrepo_c rpm" | tee -a "$LOGFILE"
  else
    echo "[i] $tool is installed." | tee -a "$LOGFILE"
  fi
done

echo "[i] Creating repo directories..." | tee -a "$LOGFILE"
mkdir -p "$BASEOS_PATH"
mkdir -p "$APPSTREAM_PATH"

# === Sync Repos ===
echo "[i] Syncing BaseOS..." | tee -a "$LOGFILE"
reposync --repo=baseos --arch="$ARCH" --download-path="$REPO_DIR" --download-metadata --norepopath &>> "$LOGFILE"

echo "[i] Syncing AppStream..." | tee -a "$LOGFILE"
reposync --repo=appstream --arch="$ARCH" --download-path="$REPO_DIR" --download-metadata --norepopath &>> "$LOGFILE"

# === Inject Group Metadata ===
echo "[i] Injecting comps files..." | tee -a "$LOGFILE"
cp "$COMPS_DIR/comps-BaseOS.xml" "$BASEOS_PATH/"
cp "$COMPS_DIR/comps-AppStream.xml" "$APPSTREAM_PATH/"

# === Rebuild Metadata ===
echo "[i] Rebuilding BaseOS metadata..." | tee -a "$LOGFILE"
createrepo_c -g "$BASEOS_PATH/comps-BaseOS.xml" "$BASEOS_PATH" &>> "$LOGFILE"

echo "[i] Rebuilding AppStream metadata with group info..." | tee -a "$LOGFILE"
createrepo_c --update -g "$APPSTREAM_PATH/comps-AppStream.xml" "$APPSTREAM_PATH" &>> "$LOGFILE"

# === DIFF 1: Official vs Local Packages ===
echo "[i] Checking for missing packages vs official Rocky repos..." | tee -a "$LOGFILE"

dnf repoquery --repo=baseos --qf "%{name}" | sort -u > /tmp/rocky_baseos.txt
dnf repoquery --repo=appstream --qf "%{name}" | sort -u > /tmp/rocky_appstream.txt

find "$BASEOS_PATH/Packages" -name "*.rpm" | xargs -n1 rpm -qp --qf "%{name}\n" | sort -u > /tmp/local_baseos.txt
find "$APPSTREAM_PATH/Packages" -name "*.rpm" | xargs -n1 rpm -qp --qf "%{name}\n" | sort -u > /tmp/local_appstream.txt

# Build master list of local package names (BaseOS + AppStream)
cat /tmp/local_baseos.txt /tmp/local_appstream.txt | sort -u > /tmp/all_local_pkgs.txt

echo -e "\n[i] Missing BaseOS packages compared to official repo:" | tee -a "$LOGFILE"
comm -23 /tmp/rocky_baseos.txt /tmp/local_baseos.txt | tee -a "$LOGFILE" || echo "[i] All BaseOS packages present." | tee -a "$LOGFILE"

echo -e "\n[i] Missing AppStream packages compared to official repo:" | tee -a "$LOGFILE"
comm -23 /tmp/rocky_appstream.txt /tmp/local_appstream.txt | tee -a "$LOGFILE" || echo "[i] All AppStream packages present." | tee -a "$LOGFILE"

# === DIFF 2A: Missing AppStream Group Packages ===
echo "🔍 Checking missing group packages from comps-AppStream.xml..." | tee -a "$LOGFILE"
grep -oP '<packagereq[^>]*>\K[^<]+' "$COMPS_DIR/comps-AppStream.xml" | sort -u > /tmp/comps_appstream_pkgs.txt

echo -e "\n[i] Missing group packages (from comps-AppStream.xml):" | tee -a "$LOGFILE"
comm -23 /tmp/comps_appstream_pkgs.txt /tmp/local_appstream.txt | tee /tmp/missing_group_appstream.txt | tee -a "$LOGFILE" || echo "[i] All AppStream group packages found." | tee -a "$LOGFILE"

# === DIFF 2B: Missing BaseOS Group Packages ===
echo "[i] Checking missing group packages from comps-BaseOS.xml..." | tee -a "$LOGFILE"
grep -oP '<packagereq[^>]*>\K[^<]+' "$COMPS_DIR/comps-BaseOS.xml" | sort -u > /tmp/comps_baseos_pkgs.txt

echo -e "\n[i] Missing group packages (from comps-BaseOS.xml):" | tee -a "$LOGFILE"
comm -23 /tmp/comps_baseos_pkgs.txt /tmp/local_baseos.txt | tee /tmp/missing_group_baseos.txt | tee -a "$LOGFILE" || echo "[i] All BaseOS group packages found." | tee -a "$LOGFILE"

# === DIFF 3: Check packages listed in both Kickstart files ===
echo "[i] Checking Kickstart-defined packages (full + light)..." | tee -a "$LOGFILE"

for KS_FILE in "$HOME/kitpro-os/kitpro-full.ks" "$HOME/kitpro-os/kitpro-light.ks"; do
  KS_NAME=$(basename "$KS_FILE")

  echo -e "\n[i] Validating $KS_NAME packages..." | tee -a "$LOGFILE"

  grep -v '^@' "$KS_FILE" | sed -n '/^%packages/,/^%end/p' | grep -vE '^(@|%|#|$)' | sort -u > "/tmp/${KS_NAME}_required.txt"

  comm -23 "/tmp/${KS_NAME}_required.txt" /tmp/all_local_pkgs.txt | tee "/tmp/missing_${KS_NAME}_pkgs.txt" | tee -a "$LOGFILE" \
    || echo "[i] All packages in $KS_NAME found." | tee -a "$LOGFILE"
done

# === DIFF 4: Download full group packages for core/base-x/fonts ===
echo -e "\n[i] Resolving group packages for @core, @base-x, @fonts..." | tee -a "$LOGFILE"

for GROUP in core base-x fonts; do
  echo "[->]  Resolving group: @$GROUP" | tee -a "$LOGFILE"
  dnf groupinfo "$GROUP" --quiet | awk '/^   / { print $1 }' >> /tmp/group_${GROUP}_pkgs.txt
done

sort -u /tmp/group_*_pkgs.txt > /tmp/full_required_group_pkgs.txt

echo "[i] Total unique packages required by groups: $(wc -l < /tmp/full_required_group_pkgs.txt)" | tee -a "$LOGFILE"

comm -23 /tmp/full_required_group_pkgs.txt /tmp/all_local_pkgs.txt | tee /tmp/missing_resolved_group_pkgs.txt | tee -a "$LOGFILE"

if [[ -s /tmp/missing_resolved_group_pkgs.txt ]]; then
  echo -e "\n[?] Auto-download missing packages from resolved groups? (y/n)"
  read -r DL_GROUPS
  if [[ "$DL_GROUPS" == "y" || "$DL_GROUPS" == "Y" ]]; then
    mkdir -p /tmp/missing_rpms_groups
    pushd /tmp/missing_rpms_groups > /dev/null

    while read -r pkg; do
      echo "[->]  Downloading $pkg (group)..." | tee -a "$LOGFILE"
      dnf download --resolve --disablerepo="*" --enablerepo=baseos,appstream "$pkg" &>> "$LOGFILE" || echo "[!] Failed to download $pkg" | tee -a "$LOGFILE"
    done < /tmp/missing_resolved_group_pkgs.txt

    # Move packages to appropriate repo
    echo "[i] Moving resolved group RPMs..." | tee -a "$LOGFILE"
    for rpm in *.rpm; do
      [[ ! -f "$rpm" ]] && continue
      rpmname=$(rpm -qp --qf "%{name}" "$rpm")
      if grep -q "$rpmname" /tmp/rocky_baseos.txt; then
        mv "$rpm" "$BASEOS_PATH/Packages/"
      elif grep -q "$rpmname" /tmp/rocky_appstream.txt; then
        mv "$rpm" "$APPSTREAM_PATH/Packages/"
      fi
    done

    echo "[i] Rebuilding metadata after group resolution..." | tee -a "$LOGFILE"
    createrepo_c --update "$BASEOS_PATH" &>> "$LOGFILE"
    createrepo_c --update -g "$APPSTREAM_PATH/comps-AppStream.xml" "$APPSTREAM_PATH" &>> "$LOGFILE"
    popd > /dev/null
  fi
fi

# === Manual Package Injection ===
echo "[i] Ensuring python3-pip is present..." | tee -a "$LOGFILE"
dnf download --resolve --disablerepo="*" --enablerepo=appstream python3-pip &>> "$LOGFILE" || echo "[!] Failed to download python3-pip" | tee -a "$LOGFILE"
find . -name "python3-pip*.rpm" | while read -r rpm; do
  if [[ "$(realpath "$rpm")" != "$(realpath "$APPSTREAM_PATH/Packages/$(basename "$rpm")")" ]]; then
    mv "$rpm" "$APPSTREAM_PATH/Packages/"
  fi
done

# === Verify Group Packages: @core, @base-x, @fonts ===
for group in core base-x fonts; do
  echo -e "\n🔎 Verifying packages in group: @$group..." | tee -a "$LOGFILE"
  dnf group info "$group" --enablerepo=baseos,appstream | grep -E '^   ' | sed 's/^ *//' | sort -u > "/tmp/group_$group.txt"
  comm -23 "/tmp/group_$group.txt" /tmp/all_local_pkgs.txt | tee "/tmp/missing_group_${group}.txt" | tee -a "$LOGFILE" \
    || echo "[i] All packages in group @$group found." | tee -a "$LOGFILE"
done

# === Prompt to Auto-Download Missing Group Packages ===
if [[ -s /tmp/missing_group_appstream.txt || -s /tmp/missing_group_baseos.txt ]]; then
  echo -e "\n[?] Do you want to auto-download the missing group packages and inject them into the repos? (y/n)"
  read -r AUTO_DL
  if [[ "$AUTO_DL" == "y" || "$AUTO_DL" == "Y" ]]; then
    echo "📦 Downloading and injecting missing group packages..." | tee -a "$LOGFILE"
    mkdir -p /tmp/missing_rpms
    pushd /tmp/missing_rpms > /dev/null

    cat /tmp/missing_group_baseos.txt /tmp/missing_group_appstream.txt | sort -u | while read -r pkg; do
      echo "[->]  Downloading $pkg..." | tee -a "$LOGFILE"
      dnf download --resolve --disablerepo="*" --enablerepo=baseos,appstream "$pkg" &>> "$LOGFILE" || echo "[!] Failed to download $pkg" | tee -a "$LOGFILE"
    done

    echo "[i] Moving RPMs to repos..." | tee -a "$LOGFILE"
    find . -name "*.rpm" | while read -r rpm; do
      rpmname=$(rpm -qp --qf "%{name}" "$rpm")
      if grep -q "$rpmname" /tmp/comps_appstream_pkgs.txt; then
        mv "$rpm" "$APPSTREAM_PATH/Packages/"
      elif grep -q "$rpmname" /tmp/comps_baseos_pkgs.txt; then
        mv "$rpm" "$BASEOS_PATH/Packages/"
      fi
    done

    echo "[i] Rebuilding metadata..." | tee -a "$LOGFILE"
    createrepo_c --update "$BASEOS_PATH" &>> "$LOGFILE"
    createrepo_c --update -g "$APPSTREAM_PATH/comps-AppStream.xml" "$APPSTREAM_PATH" &>> "$LOGFILE"

    popd > /dev/null
  fi
else
  echo "[i] No missing group packages to auto-download." | tee -a "$LOGFILE"
fi

# === Strip unneeded RPMs based on Kickstart + Groups ===
echo -e "\n[i] Cleaning up unneeded RPMs..." | tee -a "$LOGFILE"

# Combine all known-required package names
sort -u \
  /tmp/full_required_group_pkgs.txt \
  /tmp/comps_appstream_pkgs.txt \
  /tmp/comps_baseos_pkgs.txt \
  /tmp/kitpro-full.ks_required.txt \
  /tmp/kitpro-light.ks_required.txt \
  > /tmp/all_required_rpms.txt

# Remove RPMs not in the required list
for repo_path in "$BASEOS_PATH/Packages" "$APPSTREAM_PATH/Packages"; do
  echo "[i] Checking $repo_path..." | tee -a "$LOGFILE"
  find "$repo_path" -name "*.rpm" | while read -r rpm; do
    rpmname=$(rpm -qp --qf "%{name}" "$rpm")
    if ! grep -qx "$rpmname" /tmp/all_required_rpms.txt; then
      echo "[i]  Removing $rpm" | tee -a "$LOGFILE"
      rm -f "$rpm"
    fi
  done
done

echo "[i] Rebuilding BaseOS metadata with comps..." | tee -a "$LOGFILE"

if [[ ! -f "$COMPS_DIR/comps-BaseOS.xml" ]]; then
  echo "[X] ERROR: comps-BaseOS.xml not found at $COMPS_DIR!" | tee -a "$LOGFILE"
  exit 1
fi

if ! createrepo_c -g "$COMPS_DIR/comps-BaseOS.xml" "$BASEOS_PATH" >> "$LOGFILE" 2>&1; then
  echo "[X] ERROR: Failed to run createrepo_c for BaseOS" | tee -a "$LOGFILE"
  exit 1
fi

echo "[i] Rebuilding AppStream metadata with comps..." | tee -a "$LOGFILE"

if [[ ! -f "$COMPS_DIR/comps-AppStream.xml" ]]; then
  echo "[X] ERROR: comps-AppStream.xml not found at $COMPS_DIR!" | tee -a "$LOGFILE"
  exit 1
fi

if ! createrepo_c -g "$COMPS_DIR/comps-AppStream.xml" "$APPSTREAM_PATH" >> "$LOGFILE" 2>&1; then
  echo "[X] ERROR: Failed to run createrepo_c for AppStream" | tee -a "$LOGFILE"
  exit 1
fi

echo "[i] Repo cleanup complete." | tee -a "$LOGFILE"

# === Cleanup ===
rm -f /tmp/rocky_*.txt /tmp/local_*.txt \
      /tmp/comps_appstream_pkgs.txt /tmp/comps_baseos_pkgs.txt \
      /tmp/missing_group_appstream.txt /tmp/missing_group_baseos.txt
rm -rf /tmp/missing_rpms

echo -e "\n[i] Diff report saved to: $LOGFILE"
echo "[i] Repo sync, metadata rebuild, and validation complete!"

echo "[i] Finished syncing, cleaning, and optimizing Rocky repos for ISO build." | tee -a "$LOGFILE"
