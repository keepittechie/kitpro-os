Name:           kitpro-branding
Version:        1.0
Release:        15%{?dist}
Summary:        Full visual theming and user profile for KITpro OS

License:        MIT
BuildArch:      noarch
Source0:        branding.tar.gz

%description
Branding files for KITpro OS, inspired by Parrot MATE layout. Includes LightDM greeter config, GTK theme settings, wallpapers, shell configs, fastfetch, and user layout via dconf.

%prep
%setup -q -n branding

%build
# Nothing to build

%install
# GTK theme
mkdir -p %{buildroot}/etc/gtk-3.0
cp -a common/gtk-3.0/settings.ini %{buildroot}/etc/gtk-3.0/

# Fastfetch
mkdir -p %{buildroot}/etc/fastfetch
cp -a common/fastfetch/config.json %{buildroot}/etc/fastfetch/

# LightDM session config
mkdir -p %{buildroot}/etc/lightdm/lightdm.conf.d
cat > %{buildroot}/etc/lightdm/lightdm.conf.d/10-user-session.conf << 'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=mate
EOF

# LightDM GTK Greeter custom config
mkdir -p %{buildroot}/etc/lightdm/lightdm-gtk-greeter.conf.d
cat > %{buildroot}/etc/lightdm/lightdm-gtk-greeter.conf.d/10-kitpro.conf << 'EOF'
[greeter]
background=/usr/share/backgrounds/kitpro-default.png
theme-name=Arc-Dark
icon-theme-name=Papirus-Dark
EOF

# Skel configs
mkdir -p %{buildroot}/etc/skel
cp -a mate/settings.ini %{buildroot}/etc/skel/.gtkrc-2.0

mkdir -p %{buildroot}/etc/skel/.config/autostart
cat > %{buildroot}/etc/skel/.config/autostart/apply-dconf.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Apply KITpro Layout
Exec=/usr/share/kitpro/postinstall/apply-dconf.sh && rm -f ~/.config/autostart/apply-dconf.desktop
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

# Wallpapers and icons
mkdir -p %{buildroot}/usr/share/backgrounds
cp -a common/wallpapers/*.png %{buildroot}/usr/share/backgrounds/

mkdir -p %{buildroot}/usr/share/pixmaps
cp -a logo/kitpro-logo.png %{buildroot}/usr/share/pixmaps/

# ZSH and P10K configs
mkdir -p %{buildroot}/usr/share/kitpro
cp -a common/zsh/.zshrc %{buildroot}/usr/share/kitpro/zshrc
cp -a common/zsh/.p10k.zsh %{buildroot}/usr/share/kitpro/p10k.zsh

# XGreeters
mkdir -p %{buildroot}/usr/share/xgreeters
cp -a xgreeters/*.desktop %{buildroot}/usr/share/xgreeters/

# dconf layout
mkdir -p %{buildroot}/usr/share/kitpro/postinstall
cp -a mate/dconf/full-dump.txt %{buildroot}/usr/share/kitpro/postinstall/
cp -a mate/dconf/mate-only.txt %{buildroot}/usr/share/kitpro/postinstall/

cat > %{buildroot}/usr/share/kitpro/postinstall/apply-dconf.sh << 'EOF'
#!/bin/bash
if command -v dconf &>/dev/null; then
  dconf load / < /usr/share/kitpro/postinstall/full-dump.txt
fi
EOF
chmod +x %{buildroot}/usr/share/kitpro/postinstall/apply-dconf.sh

# Optional backup configs
mkdir -p %{buildroot}/usr/share/kitpro/defaults
cp -a lightdm/*.conf %{buildroot}/usr/share/kitpro/defaults/ || :
cp -a lightdm/lightdm.conf.d/*.conf %{buildroot}/usr/share/kitpro/defaults/ || :

%files
%config(noreplace) /etc/gtk-3.0/settings.ini
%config(noreplace) /etc/lightdm/lightdm.conf.d/10-user-session.conf
%config(noreplace) /etc/lightdm/lightdm-gtk-greeter.conf.d/10-kitpro.conf
%config(noreplace) /etc/skel/.gtkrc-2.0
%config(noreplace) /etc/skel/.config/autostart/apply-dconf.desktop
%config(noreplace) /etc/fastfetch/config.json

/usr/share/xgreeters/*
/usr/share/backgrounds/*
/usr/share/pixmaps/kitpro-logo.png
/usr/share/kitpro/zshrc
/usr/share/kitpro/p10k.zsh
/usr/share/kitpro/postinstall/full-dump.txt
/usr/share/kitpro/postinstall/mate-only.txt
/usr/share/kitpro/postinstall/apply-dconf.sh
/usr/share/kitpro/defaults/*

%post
# Copy custom ZSH config for new users
if [ ! -f /etc/skel/.zshrc ]; then
  cp -a /usr/share/kitpro/zshrc /etc/skel/.zshrc
fi
if [ ! -f /etc/skel/.p10k.zsh ]; then
  cp -a /usr/share/kitpro/p10k.zsh /etc/skel/.p10k.zsh
fi

%changelog
* Mon May 27 2025 Joshua Lacy <josh@kitpro.us> - 1.0-15
- Added greeter-session=lightdm-gtk-greeter to 10-user-session.conf
- Added lightdm-gtk-greeter.conf.d/10-kitpro.conf to set greeter background and theme
- Ensures proper branding and user experience at login screen
