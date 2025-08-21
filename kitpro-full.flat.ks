#version=ROCKY10
# KITpro OS - Full MATE Install
# Maintained by Josh @ KeepItTechie

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

cdrom

repo --name=KITpro-BaseOS --baseurl=file:///run/install/repo/BaseOS
repo --name=KITpro-AppStream --baseurl=file:///run/install/repo/AppStream

rootpw --lock

%packages
@base-x
@fonts
kernel
kernel-core
kernel-modules
zsh
flatpak
gnome-disk-utility
gnome-software
curl
wget
nano
vim
bash-completion
network-manager-applet
NetworkManager
openssh-server
python3-pip
rsync
man-db
man-pages
dnf-plugins-core
xfsprogs
gvfs
gvfs-fuse
gsettings-desktop-schemas
glib2
dbus-x11
gnome-keyring
dconf-editor
xorg-x11-drivers
mesa-dri-drivers
mesa-libGL
mesa-libEGL
%end

%packages
@^minimal-environment
sddm
labwc
xwayland
xdg-desktop-portal
xdg-desktop-portal-wlr
xdg-desktop-portal-gtk
xfce4-session
xfce4-panel
xfce4-settings
xfce4-terminal
thunar
thunar-archive-plugin
xfce4-power-manager
gvfs
gvfs-mtp
network-manager-applet
polkit-gnome
wl-clipboard
grim
slurp
swaybg
pipewire
pipewire-pulse
wireplumber
firefox
adwaita-gtk3-theme
%end

%post

LOGFILE="/var/log/kitpro-post.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo ">>> KITpro OS post-install starting..."

hostnamectl set-hostname kitpro-os

# Enable EPEL + CRB
dnf install -y epel-release
dnf config-manager --set-enabled crb
dnf update -y

# Brave repo
cat <<EOF > /etc/yum.repos.d/brave-browser.repo
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF

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

# Desktop software groups
install_group() {
  echo ">>> Installing: $1"
  dnf install -y $1 || echo "⚠️ Failed: $1"
}

# MATE Desktop + Tools
install_group "NetworkManager-*"
install_group "adwaita-gtk2-theme alsa-plugins-pulseaudio atril caja caja-* dconf-editor engrampa eom gstreamer1-plugins-ugly-free gtk2-engines gucharmap gvfs-* initial-setup-gui"
install_group "libmate* marco mate-* mozo seahorse seahorse-caja"
install_group "xdg-utils xdg-user-dirs xdg-user-dirs-gtk"
install_group "git util-linux-user powerline-fonts fonts-dejavu fontawesome-fonts"

# LightDM + theming
install_group "lightdm lightdm-gtk-greeter lightdm-settings slick-greeter papirus-icon-theme"

# Extra GUI apps
install_group "fastfetch thunderbird keepassxc libreoffice btop gparted vlc pavucontrol"

# Brave browser
install_group "brave-browser"

# Docker
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
install_group "docker-ce docker-ce-cli containerd.io"

# KITpro branding
install_group "kitpro-branding arc-theme mate-menu"

# Patch LightDM greeter if present
GREETER_CONF="/etc/lightdm/lightdm-gtk-greeter.conf"
if [ -f "$GREETER_CONF" ]; then
  cp -n "$GREETER_CONF" "$GREETER_CONF.bak"
  sed -i '/^\[greeter\]/a background=/usr/share/backgrounds/kitpro-default.png' "$GREETER_CONF"
  sed -i '/^\[greeter\]/a theme-name=Arc-Dark' "$GREETER_CONF"
  sed -i '/^\[greeter\]/a icon-theme-name=Papirus-Dark' "$GREETER_CONF"
  sed -i '/^\[greeter\]/a font-name=Ubuntu 12' "$GREETER_CONF"
  echo "✅ Patched $GREETER_CONF for KITpro theming"
fi

# Enable system services
systemctl enable lightdm
systemctl enable docker || true
systemctl start docker || true
systemctl enable initial-setup
systemctl set-default graphical.target

# Branding and config to /etc/skel for future users
cp -r /branding/common/gtk-3.0 /etc/skel/.config/
cp -r /branding/common/wallpapers /usr/share/backgrounds/kitpro/
cp -r /branding/common/fastfetch/config.json /etc/fastfetch/config.json

mkdir -p /etc/skel/.config/xfce4/terminal
cp -r /branding/xfce4/terminal/terminalrc /etc/skel/.config/xfce4/terminal/

mkdir -p /etc/skel/.config/Thunar
cp -r /branding/xfce4/Thunar/thunarrc /etc/skel/.config/Thunar/

mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
cp -r /branding/xfce4/xfconf/xfce-perchannel-xml/* /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/

echo "exec startxfce4" > /etc/skel/.xinitrc

# Polkit agent
mkdir -p /etc/xdg/autostart/
cat <<EOF > /etc/xdg/autostart/polkit-gnome-authentication-agent-1.desktop
[Desktop Entry]
Type=Application
Name=PolicyKit Authentication Agent
Exec=/usr/libexec/xfce-polkit
OnlyShowIn=XFCE;
EOF

# MOTD
echo "KITpro OS customization complete!" > /etc/motd

# Schema recompile
glib-compile-schemas /usr/share/glib-2.0/schemas/ || true

# Set zsh as default shell for UID 1000 (if exists)
USERNAME=$(getent passwd 1000 | cut -d: -f1)
if [ -n "$USERNAME" ]; then
  chsh -s /bin/zsh "$USERNAME"
fi

# Future users default shell
sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd

dnf clean all
echo ">>> Post install complete."

%end

%post --nochroot
LOGFILE="/mnt/sysimage/var/log/kitpro-post.log"
echo ">>> [NoChroot] Starting setup..." >> "$LOGFILE"

# Enable Initial Setup GUI
if [ -f /mnt/sysimage/usr/lib/systemd/system/initial-setup-graphical.service ]; then
  chroot /mnt/sysimage systemctl enable initial-setup-graphical.service
  chroot /mnt/sysimage systemctl reenable initial-setup.service
else
  echo "⚠️ initial-setup-graphical.service not found" >> "$LOGFILE"
fi

echo ">>> [NoChroot] Done." >> "$LOGFILE"
%end
