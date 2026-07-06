{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  hatchling,
  anyascii,
  appdirs,
  dbus-python,
  evdev,
  hyprpy,
  i3ipc,
  inotify-simple,
  ordered-set,
  pywayland,
  python-xlib,
}:

buildPythonPackage (finalAttrs: {
  pname = "xwaykeyz";
  version = "1.22.0";
  pyproject = true;

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "RedBearAK";
    repo = "xwaykeyz";
    rev = "1615a4dcdcdc3d6d135322cd7401c882e28fbf2b";
    hash = "sha256-Og5IvGo95aafL4dV78hLZACd3FqNfrvWwDMvNa43JwI=";
  };

  build-system = [ hatchling ];

  dependencies = [
    anyascii
    appdirs
    dbus-python
    evdev
    hyprpy
    i3ipc
    inotify-simple
    ordered-set
    pywayland
    python-xlib
  ];

  pythonRelaxDeps = [
    "dbus-python"
    "evdev"
    "hyprpy"
    "inotify-simple"
    "python-xlib"
  ];

  pythonImportsCheck = [ "xwaykeyz" ];

  meta = {
    description = "Linux keymapper for X11 and Wayland, with per-app capability";
    homepage = "https://github.com/RedBearAK/xwaykeyz";
    license = lib.licenses.gpl3Plus;
    mainProgram = "xwaykeyz";
    maintainers = with lib.maintainers; [ _4evy ];
    platforms = lib.platforms.linux;
  };
})
