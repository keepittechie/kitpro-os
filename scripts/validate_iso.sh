#!/bin/bash

ISO_PATH="/opt/output/KITproOS-9.5-dual.iso"
MOUNT_DIR="/mnt/iso-test"
REQUIRED_TREEINFO_FIELDS=("release.name" "release.short" "release.version" "base_product.short" "general.short")
REQUIRED_IMAGES=("images/install.img" "images/pxeboot/vmlinuz" "images/pxeboot/initrd.img")
REQUIRED_REPO_DIRS=("BaseOS/os" "AppStream/os" "BaseOS/os/repodata" "AppStream/os/repodata")
LOGFILE="$HOME/kitpro-os/iso-validate-$(date +%Y%m%d-%H%M%S).log"

exec > >(tee -a "$LOGFILE") 2>&1

ERRORS=0

# Step 1: Mount ISO
echo -e "\n[->] Mounting ISO: $ISO_PATH"
sudo mkdir -p "$MOUNT_DIR"
sudo mount -o loop "$ISO_PATH" "$MOUNT_DIR" || { echo "[X] Failed to mount ISO."; exit 1; }

# Step 2: Validate .treeinfo
TREEINFO_PATH="$MOUNT_DIR/.treeinfo"
echo -e "\n[->] Validating .treeinfo..."
if [ ! -f "$TREEINFO_PATH" ]; then
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

# Step 3: Validate image files
echo -e "\n[->] Validating image files..."
for IMG in "${REQUIRED_IMAGES[@]}"; do
    if [ ! -f "$MOUNT_DIR/$IMG" ]; then
        echo "[X] Missing file: $IMG"
        ((ERRORS++))
    else
        echo "[OK] Found $IMG"
    fi

    file "$MOUNT_DIR/$IMG"
done

# Step 4: Volume Label Check
VOLUME_LABEL=$(isoinfo -d -i "$ISO_PATH" | grep 'Volume id:' | cut -d: -f2 | xargs)
echo -e "\n[->] Volume Label: $VOLUME_LABEL"
if [[ "$VOLUME_LABEL" != KITproOS-9.5 ]]; then
    echo "[X] Volume label mismatch (expected KITproOS-9.5)"
    ((ERRORS++))
else
    echo "[OK] Volume label correct"
fi

# Step 5: Repo Structure Check
echo -e "\n[->] Validating repo directories..."
for DIR in "${REQUIRED_REPO_DIRS[@]}"; do
    if [ ! -d "$MOUNT_DIR/$DIR" ]; then
        echo "[X] Missing directory: $DIR"
        ((ERRORS++))
    else
        echo "[OK] Directory exists: $DIR"
    fi
done

# Step 6: Validate core group packages
REPO_PATHS=("BaseOS/os" "AppStream/os")
for COMPS in comps-BaseOS.xml comps-AppStream.xml; do
    echo -e "\n[->] Checking packages defined in $COMPS"
    grep -oP '<packagereq[^>]*>\K[^<]+' "$HOME/kitpro-os/comps/$COMPS" | sort -u > /tmp/comps-expected.txt

    for REPO in "${REPO_PATHS[@]}"; do
        find "$MOUNT_DIR/$REPO/Packages" -name "*.rpm" 2>/dev/null | \
            xargs -n1 rpm -qp --qf "%{name}\n" 2>/dev/null | sort -u > /tmp/comps-actual.txt
    done

    echo "[!] Missing packages in $COMPS:"
    comm -23 /tmp/comps-expected.txt /tmp/comps-actual.txt || echo "[OK] All packages found in ISO."
done

# Step 7: Optional Rocky diff
if [ -d "/mnt/rocky-boot" ]; then
    echo -e "\n[->] Comparing to official Rocky ISO..."
    DIFF_OUT=$(diff -rq /mnt/rocky-boot "$MOUNT_DIR" | grep -v "Files .* differ")
    if [ -n "$DIFF_OUT" ]; then
        echo "[!] Differences found:"
        echo "$DIFF_OUT"
    else
        echo "[OK] Structure matches Rocky ISO."
    fi
fi

# Step 8: Unmount
echo -e "\n[->] Unmounting ISO..."
sudo umount "$MOUNT_DIR"

# Final Result
echo -e "\n[->] Validation complete. Log saved to: $LOGFILE"
if [ "$ERRORS" -eq 0 ]; then
    echo "[OK] ISO is valid."
    exit 0
else
    echo "[X] ISO has $ERRORS issue(s)."
    exit 1
fi
