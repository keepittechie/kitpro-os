#version=RHEL9
# KITpro OS - Light XFCE Install
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
@xfce
zsh
vim
nano
wget
curl
NetworkManager
openssh-server
firewalld
xfce4-terminal
bash-completion
gnome-disk-utility
%end

%include kickstarts/includes/xfce-wayland.ks.inc

%post --log=/var/log/kitpro-post.log
echo ">>> KITpro OS post-install starting..."

# Set hostname
hostnamectl set-hostname kitpro-os

# Enable EPEL and CRB
dnf install -y epel-release
dnf config-manager --set-enabled crb
dnf update -y

# Brave browser repo
cat <<EOF > /etc/yum.repos.d/brave-browser.repo
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF

# Install LightDM and extras
dnf install -y \
  initial-setup-gui lightdm lightdm-gtk-greeter lightdm-settings \
  xfce-polkit thunar-archive-plugin fastfetch \
  brave-browser || true

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

# Install KITpro branding
dnf install -y arc-theme

# Enable graphical login
systemctl set-default graphical.target
systemctl enable lightdm
systemctl enable initial-setup

# Apply XFCE branding (will apply to user created at first boot)
cp -r /branding/common/gtk-3.0 /etc/skel/.config/
cp -r /branding/common/wallpapers /usr/share/backgrounds/kitpro/
cp /branding/common/fastfetch/config.json /etc/fastfetch/config.json

mkdir -p /etc/skel/.config/xfce4/terminal
cp -r /branding/xfce4/terminal/terminalrc /etc/skel/.config/xfce4/terminal/

mkdir -p /etc/skel/.config/Thunar
cp -r /branding/xfce4/Thunar/thunarrc /etc/skel/.config/Thunar/

mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
cp -r /branding/xfce4/xfconf/xfce-perchannel-xml/* /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/

# Enable polkit agent
mkdir -p /etc/xdg/autostart/
cat <<EOF > /etc/xdg/autostart/polkit-gnome-authentication-agent-1.desktop
[Desktop Entry]
Type=Application
Name=PolicyKit Authentication Agent
Exec=/usr/libexec/xfce-polkit
OnlyShowIn=XFCE;
EOF

# Set up autologin placeholder — user will be set by initial setup
mkdir -p /etc/lightdm/lightdm.conf.d/
echo -e "[Seat:*]\ngreeter-session=lightdm-gtk-greeter" > /etc/lightdm/lightdm.conf.d/10-autologin.conf

# Fallback wallpaper (may get overridden later)
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path -s /usr/share/backgrounds/kitpro/kitpro-default.png || true

echo "exec startxfce4" > /etc/skel/.xinitrc

echo ">>> Post install finished"
%end
