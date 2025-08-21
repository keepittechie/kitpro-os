KS="/opt/kitpro-os/kitpro-full.flat.ks"
IN="/opt/kitpro-os/iso/Rocky-10.0-x86_64-dvd.iso"
OUT="/opt/kitpro-os/output/KITproOS-10.0-$(date +%Y%m%d).iso"

# Only add overlay dirs that actually have files (your /etc/ currently does; /usr will once you add those files)
mkksiso \
  --ks "$KS" \
  -a "/opt/kitpro-os/iso-overlay/etc:/etc" \
  "$IN" \
  "$OUT"
