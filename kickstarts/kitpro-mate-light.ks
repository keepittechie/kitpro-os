#version=ROCKY10
lang en_US.UTF-8
keyboard us
timezone America/Los_Angeles --utc
reboot
cdrom

bootloader --append="rhgb quiet inst.graphical crashkernel=auto"
zerombr
clearpart --all --initlabel
autopart

network --hostname=kitpro-os --bootproto=dhcp --device=link --activate
firstboot --enable
selinux --enforcing
firewall --enabled --service=ssh

repo --name=AppStream --baseurl=file:///run/install/repo/AppStream
repo --name=BaseOS --baseurl=file:///run/install/repo/BaseOS

rootpw --lock

%packages
@base-x
@fonts
kernel
kernel-core
kernel-modules
zsh
flatpak
curl
wget
nano
vim
bash-completion
network-manager-applet
NetworkManager
openssh-server
%end


%post

# Set up logging
LOGFILE="/var/log/kitpro-post.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo ">>> KITpro OS post install starting..."

# Set hostname
hostnamectl set-hostname kitpro-os

# Enable EPEL and CRB
dnf install -y epel-release
dnf config-manager --set-enabled crb
dnf update -y

# Add Brave browser repo
cat <<EOF > /etc/yum.repos.d/brave-browser.repo
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF

# Define function to install and log each group
install_group() {
  echo ">>> Installing $1..."
  dnf install -y $1
  if [ $? -ne 0 ]; then
    echo "⚠️ Failed to install: $1"
  fi
}

# Split into chunks
install_group "NetworkManager-adsl NetworkManager-bluetooth NetworkManager-libreswan-gnome NetworkManager-openvpn-gnome NetworkManager-ovs NetworkManager-ppp NetworkManager-team NetworkManager-wifi NetworkManager-wwan"
install_group "adwaita-gtk2-theme alsa-plugins-pulseaudio atril atril-caja atril-thumbnailer caja caja-actions caja-image-converter caja-open-terminal caja-sendto caja-wallpaper caja-xattr-tags dconf-editor engrampa eom"
install_group "firewall-config gnome-disk-utility gnome-epub-thumbnailer gstreamer1-plugins-ugly-free gtk2-engines gucharmap gvfs-fuse gvfs-gphoto2 gvfs-mtp gvfs-smb initial-setup-gui"
install_group "libmatekbd libmatemixer libmateweather libsecret lm_sensors marco mate-applets mate-backgrounds mate-calc mate-control-center mate-desktop mate-dictionary"
install_group "mate-disk-usage-analyzer mate-icon-theme mate-media mate-menus gnome-themes-extra mate-menus-preferences-category-menu mate-notification-daemon mate-panel mate-polkit"
install_group "mate-power-manager mate-screensaver mate-screenshot mate-search-tool xdg-utils mate-session-manager mate-settings-daemon mate-system-log mate-system-monitor mate-terminal mate-themes mate-user-admin mate-user-guide mozo"
install_group "network-manager-applet nm-connection-editor p7zip p7zip-plugins pluma seahorse seahorse-caja xdg-user-dirs xdg-user-dirs-gtk initial-setup git util-linux-user powerline-fonts fonts-dejavu fontawesome-fonts"

# LightDM and greeter
install_group "lightdm lightdm-gtk-greeter lightdm-settings slick-greeter papirus-icon-theme"

# Extras
install_group "fastfetch htop gparted pavucontrol"

# Brave browser
install_group "brave-browser"

# Set permissions for RPMs
chmod -R a+r /run/install/repo/branding/packages/

# KITpro repo
cat <<EOF > /etc/yum.repos.d/kitpro.repo
[kitpro]
name=KITpro OS Repository
baseurl=https://repo.kitpro.us/9/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://repo.kitpro.us/RPM-GPG-KEY-KITPRO
EOF

rpm --import https://repo.kitpro.us/RPM-GPG-KEY-KITPRO

# KITpro branding packages
install_group "kitpro-branding arc-theme mate-menu"

# Safely patch LightDM GTK Greeter if present
GREETER_CONF="/etc/lightdm/lightdm-gtk-greeter.conf"
if [ -f "$GREETER_CONF" ]; then
  cp -n "$GREETER_CONF" "$GREETER_CONF.bak"
  sed -i '/^\[greeter\]/a background=/usr/share/backgrounds/kitpro-default.png' "$GREETER_CONF"
  sed -i '/^\[greeter\]/a theme-name=Arc-Dark' "$GREETER_CONF"
  sed -i '/^\[greeter\]/a icon-theme-name=Papirus-Dark' "$GREETER_CONF"
  sed -i '/^\[greeter\]/a font-name=Ubuntu 12' "$GREETER_CONF"
  echo "✅ Patched $GREETER_CONF for KITpro theming" >> /var/log/kitpro-post.log
fi

# Enable key services
systemctl enable lightdm
systemctl enable initial-setup

# Set graphical target
systemctl set-default graphical.target

# Set default shell to zsh for UID 1000
USERNAME=$(getent passwd 1000 | cut -d: -f1)
if [ -n "$USERNAME" ]; then
  chsh -s /bin/zsh "$USERNAME" || echo "Failed to set zsh for $USERNAME"
fi

# Set Zsh as default for future users
sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd

# Compile schemas for GTK
if [ -d /usr/share/glib-2.0/schemas ]; then
  glib-compile-schemas /usr/share/glib-2.0/schemas/
fi

# MOTD
echo "KITpro OS customization complete!" > /etc/motd

# Final log
echo ">>> KITpro OS post install complete."

%end


%post --nochroot

# Enable Initial Setup GUI from outside the chroot
echo ">>> Enabling initial-setup-graphical.service..."
if [ -f /mnt/sysimage/usr/lib/systemd/system/initial-setup-graphical.service ]; then
  chroot /mnt/sysimage systemctl enable initial-setup-graphical.service
else
  echo "initial-setup-graphical.service not found, skipping..." >> /mnt/sysimage/var/log/kitpro-post.log
fi

# ✅ Enable Initial Setup GUI on first boot
if [ -f /usr/lib/systemd/system/initial-setup-graphical.service ]; then
  systemctl enable initial-setup-graphical.service
  systemctl reenable initial-setup.service
fi

# ✅ Add temporary user if no user exists (prevents login lockout)
if ! id "kituser" &>/dev/null; then
  useradd -m -G wheel -s /bin/bash kituser
  echo "kituser:kitpass" | chpasswd
  echo "Temporary user 'kituser' created with password 'kitpass'" >> /var/log/kitpro-post.log
fi

# Final log
echo ">>> KITpro OS post install complete." >> /var/log/kitpro-post.log
echo ">>> KITpro OS post install complete."
%end
