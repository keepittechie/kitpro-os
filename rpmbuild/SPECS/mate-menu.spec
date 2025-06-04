Name:           mate-menu
Version:        24.04
Release:        1%{?dist}
Summary:        Advanced menu for the MATE Desktop Environment

License:        GPLv2+
URL:            https://github.com/ubuntu-mate/mate-menu
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch

BuildRequires:  gettext
BuildRequires:  python3-devel
Requires:       python3-gobject
Requires:       python3-configobj
Requires:       python3-setproctitle
Requires:       python3-pyxdg
Requires:       mate-panel
Requires:       mate-menus
Requires:       python3-gobject
Requires:       python3-configobj
Requires:       python3-setproctitle
Requires:       python3-pyxdg
Requires:       python3-xlib

%description
Mate Menu is a full-featured advanced menu for the MATE desktop environment,
supporting search, favorites, plugins, and customization.

%prep
%autosetup

%build
# No compilation required

%install
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/lib/mate-menu
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/48x48/apps
mkdir -p %{buildroot}/usr/share/mate-menu/plugins
mkdir -p %{buildroot}/usr/share/mate-menu/icons
mkdir -p %{buildroot}/usr/share/glib-2.0/schemas
mkdir -p %{buildroot}/usr/share/mate-panel/applets
mkdir -p %{buildroot}/usr/share/dbus-1/services
mkdir -p %{buildroot}/usr/share/man/man1

# Main scripts
install -m 755 lib/mate-menu.py %{buildroot}/usr/lib/mate-menu/
install -m 755 lib/mate-menu-config.py %{buildroot}/usr/lib/mate-menu/

# Launcher
desktop-file-install --dir=%{buildroot}/usr/share/applications data/mate-menu.desktop

# Install main application icon
install -D -m 644 data/icons/mate-menu.png %{buildroot}/usr/share/icons/hicolor/48x48/apps/mate-menu.png
install -D -m 644 data/icons/mate-menu.png %{buildroot}/usr/share/mate-menu/icons/mate-menu.png

# UI Files
install -m 644 data/mate-menu.glade %{buildroot}/usr/share/mate-menu/
install -m 644 data/mate-menu-config.glade %{buildroot}/usr/share/mate-menu/
install -m 644 data/popup.xml %{buildroot}/usr/share/mate-menu/
install -m 644 data/applications.list %{buildroot}/usr/share/mate-menu/

# Plugins
install -m 644 data/plugins/*.glade %{buildroot}/usr/share/mate-menu/plugins/

# Icons (ignore error if they don't exist)
cp -a data/icons/*.png %{buildroot}/usr/share/mate-menu/icons/ 2>/dev/null || :

# Python package directory
cp -a mate_menu %{buildroot}/usr/lib/mate-menu/

# Schemas
install -m 644 data/*.gschema.xml %{buildroot}/usr/share/glib-2.0/schemas/
install -m 644 data/plugins/*.gschema.xml %{buildroot}/usr/share/glib-2.0/schemas/

# Applet and DBus
install -m 644 data/*.mate-panel-applet %{buildroot}/usr/share/mate-panel/applets/
install -m 644 data/*.service %{buildroot}/usr/share/dbus-1/services/

# Manpage
gzip -c data/mate-menu.1 > %{buildroot}/usr/share/man/man1/mate-menu.1.gz || :

%files
%license COPYING
%doc README.md

/usr/lib/mate-menu/mate-menu.py
/usr/lib/mate-menu/mate_menu/
/usr/lib/mate-menu/mate-menu-config.py

/usr/share/applications/mate-menu.desktop
/usr/share/icons/hicolor/48x48/apps/mate-menu.png
/usr/share/mate-menu/icons/mate-menu.png

/usr/share/mate-menu/*
/usr/share/mate-menu/plugins/*
/usr/share/mate-menu/icons/*

/usr/share/glib-2.0/schemas/*.xml
/usr/share/mate-panel/applets/*.mate-panel-applet
/usr/share/dbus-1/services/*.service
/usr/share/man/man1/mate-menu.1.gz

%changelog
* Tue May 20 2025 Joshua Lacy <josh@kitpro.us> - 24.04-1
- Fully manual install, removed %py3_install to avoid script build issues
