Name:           arc-theme
Version:        2025
Release:        2%{?dist}
Summary:        A flat theme with transparent elements for GTK 3, GTK 2, GTK 4, and GNOME Shell

License:        GPLv3+
URL:            https://github.com/horst3180/arc-theme
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  sassc
BuildRequires:  gtk3-devel
BuildRequires:  glib2-devel
BuildRequires:  gnome-themes-extra

%global debug_package %{nil}

%description
Arc is a flat theme with transparent elements for GTK 2, GTK 3, GTK 4, GNOME Shell, and window managers like XFWM and Metacity.

%prep
%autosetup -n arc-theme

%build
mkdir build
cd build
meson .. \
  --prefix=/usr \
  -Dthemes=gtk2,gtk3,gtk4,metacity,plank,xfwm \
  -Dvariants=light,darker,dark \
  -Dtransparency=true \
  -Dcinnamon_version=0
ninja

%install
cd build
DESTDIR=%{buildroot} ninja install

%files
%license COPYING
/usr/share/themes/Arc*

%changelog
* Sat May 25 2025 Joshua Lacy <josh@kitpro.us> - 2025-2.el9
- Rebuild: adjusted build settings for GTK variants and transparency
- Minor spec cleanup for clarity and alignment with KITpro packaging style

* Fri May 24 2025 Joshua Lacy <josh@kitpro.us> - 2025-1.el9
- Initial RPM build for KITpro OS with full Arc theme variants and transparency support
