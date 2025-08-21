#!/usr/bin/env bash
set -euo pipefail

# Safety: require running from repo root
[[ -f "README.md" || -f "LICENSE" || -d ".git" ]] || { echo "Run from repo root."; exit 1; }

echo "This will REMOVE build artifacts and large binaries:"
cat <<'LIST'
- output/ (built ISOs)
- iso/*.iso (source ISOs you downloaded)
- .iso-work/ (temp ISO extraction)
- EFI/, images/, isolinux/ (extracted from ISO)
- repos/ (local mirrors/caches)  [kept: repos/mirrorlist only]
- rpmbuild/BUILD, BUILDROOT, RPMS, SRPMS (keeps SPECS & SOURCES)
- tmp/
LIST

read -rp "Proceed? [y/N] " ok
[[ "${ok:-N}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# Remove heavy/generated content
rm -rf \
  output \
  .iso-work \
  tmp \
  EFI \
  images \
  isolinux

# Keep repos/mirrorlist; drop everything else under repos/
if [[ -d repos ]]; then
  find repos -mindepth 1 -not -name 'mirrorlist' -exec rm -rf {} +
fi

# Remove downloaded ISO(s)
rm -f iso/*.iso || true

# Clean rpmbuild outputs but keep SOURCES & SPECS
rm -rf rpmbuild/BUILD rpmbuild/BUILDROOT rpmbuild/RPMS rpmbuild/SRPMS

echo "[✓] Cleanup complete."

# Create/merge .gitignore
cat > .gitignore <<'GIT'
# Build outputs
/output/
/.iso-work/
/tmp/
/*.iso

# ISO source + extracts
/iso/*.iso
/EFI/
/images/
/isolinux/

# Local repo mirrors/caches
/repos/*
!/repos/mirrorlist

# RPM build outputs
/rpmbuild/BUILD/
/rpmbuild/BUILDROOT/
/rpmbuild/RPMS/
/rpmbuild/SRPMS/

# Editor/OS junk
.DS_Store
Thumbs.db
*.swp
.idea/
.vscode/
GIT

echo "[i] Wrote/updated .gitignore"
