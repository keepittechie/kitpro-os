#version=ROCKY10
lang en_US.UTF-8
keyboard us
timezone America/Los_Angeles --utc
reboot
cdrom

bootloader --append="rhgb quiet"
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
@Xfce
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
xrandr
%end

%post --log=/var/log/kitpro-post.log
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

# Install LightDM + Polkit agent (still from EPEL)
dnf install -y lightdm lightdm-gtk-greeter lightdm-settings xfce-polkit thunar-archive-plugin fastfetch

# Extras
dnf install -y fastfetch thunderbird keepassxc libreoffice btop gparted vlc pavucontrol

# Brave browser
dnf install -y brave-browser || true

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
dnf install -y kitpro-branding arc-theme

# Enable graphical login
systemctl set-default graphical.target
systemctl enable lightdm

# Create default user
useradd -m -G wheel -s /bin/zsh kituser
echo 'kituser:kitpro' | chpasswd

# Apply branding from install media
mkdir -p /home/kituser/.config/xfce4/terminal
cp -r /run/install/repo/branding/xfce4/terminal/terminalrc /home/kituser/.config/xfce4/terminal/

mkdir -p /home/kituser/.config/Thunar
cp -r /run/install/repo/branding/xfce4/Thunar/thunarrc /home/kituser/.config/Thunar/

mkdir -p /home/kituser/.config/xfce4/xfconf/xfce-perchannel-xml
cp -r /run/install/repo/branding/xfce4/xfconf/xfce-perchannel-xml/* /home/kituser/.config/xfce4/xfconf/xfce-perchannel-xml/

mkdir -p /home/kituser/.config
mkdir -p /usr/share/backgrounds/kitpro
cp -r /run/install/repo/branding/common/gtk-3.0 /home/kituser/.config/
cp -r /run/install/repo/branding/common/wallpapers/. /usr/share/backgrounds/kitpro/
cp /run/install/repo/branding/common/zsh/.zshrc /home/kituser/.zshrc
cp /run/install/repo/branding/common/zsh/.p10k.zsh /home/kituser/.p10k.zsh
cp /run/install/repo/branding/common/fastfetch/config.json /etc/fastfetch/config.json

chown -R kituser:kituser /home/kituser

# Optional fallback wallpaper
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path -s /usr/share/backgrounds/kitpro/kitpro-default.png || true

# Enable polkit agent
mkdir -p /etc/xdg/autostart/
cat <<EOF > /etc/xdg/autostart/polkit-gnome-authentication-agent-1.desktop
[Desktop Entry]
Type=Application
Name=PolicyKit Authentication Agent
Exec=/usr/libexec/xfce-polkit
OnlyShowIn=XFCE;
EOF

echo ">>> Post install finished"
%end

%post --nochroot
echo ">>> [NoChroot] Enabling initial-setup-graphical.service..."
if [ -f /mnt/sysimage/usr/lib/systemd/system/initial-setup-graphical.service ]; then
  chroot /mnt/sysimage systemctl enable initial-setup-graphical.service
  chroot /mnt/sysimage systemctl reenable initial-setup.service
else
  echo "⚠️ initial-setup-graphical.service not found" >> /mnt/sysimage/var/log/kitpro-post.log
fi

# Fallback user creation
chroot /mnt/sysimage id kituser &>/dev/null || (
  chroot /mnt/sysimage useradd -m -G wheel -s /bin/zsh kituser
  echo 'kituser:kitpro' | chroot /mnt/sysimage chpasswd
)
%end
