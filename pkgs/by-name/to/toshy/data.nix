{
  lib,
  outputPath,
  runtimeShell,
  toshyShare,
  runtimePath,
  libx11,
  xkeyboard-config,
  xwaykeyz,
  nixosModuleMessage,
  nixosAutostartMessage,
}:

{
  toshyFiles = [
    "assets"
    "cosmic-dbus-service"
    "default-toshy-config"
    "kwin-dbus-service"
    "kwin-script"
    "toshy_common"
    "toshy_gui"
    "wlroots-dbus-service"
    "toshy_layout_selector.py"
    "toshy_tray.py"
  ];

  iconNames = [
    "toshy_app_icon_rainbow"
    "toshy_app_icon_rainbow_inverse"
    "toshy_app_icon_rainbow_inverse_grayscale"
  ];

  runtimeScripts = [
    "scripts/bin/toshy-services-log.sh"
    "scripts/bin/toshy-services-restart.sh"
    "scripts/bin/toshy-services-start.sh"
    "scripts/bin/toshy-services-status.sh"
    "scripts/bin/toshy-services-stop.sh"
    "scripts/toshy-kwin-script-kickstart.sh"
    "scripts/toshy_versions.py"
    "scripts/tshysvc-config"
    "scripts/tshysvc-sessmon"
  ];

  sessionVariables = [
    "DBUS_SESSION_BUS_ADDRESS"
    "DESKTOP_SESSION"
    "DISPLAY"
    "HYPRLAND_INSTANCE_SIGNATURE"
    "KDE_SESSION_VERSION"
    "PATH"
    "SWAYSOCK"
    "WAYFIRE_CONFIG_FILE"
    "WAYFIRE_SOCKET"
    "WAYLAND_DISPLAY"
    "XAUTHORITY"
    "XDG_CURRENT_DESKTOP"
    "XDG_RUNTIME_DIR"
    "XKB_CONFIG_ROOT"
    "XDG_SESSION_DESKTOP"
    "XDG_SESSION_TYPE"
  ];

  substitutions = [
    {
      files = [ "${toshyShare}/toshy_common/service_manager.py" ];
      replacements = [
        {
          from = "self.home_local_bin = os.path.join(self.home_dir, '.local', 'bin')";
          to = "self.home_local_bin = '${outputPath}/bin'";
        }
        {
          from = ''enable_cmd_base = ["systemctl", "--user", "enable"]'';
          to = ''enable_cmd_base = ["true"]'';
        }
        {
          from = ''disable_cmd_base = ["systemctl", "--user", "disable"]'';
          to = ''disable_cmd_base = ["true"]'';
        }
        {
          from = ''message = "Toshy services ENABLED. Will autostart at login."'';
          to = ''message = "${nixosModuleMessage}"'';
        }
        {
          from = ''message = "Toshy systemd services DISABLED. Will not autostart."'';
          to = ''message = "${nixosModuleMessage}"'';
        }
      ];
    }
    {
      files = [ "${toshyShare}/scripts/tshysvc-config" ];
      replacements = [
        {
          from = "export PATH=$HOME/.local/bin:$PATH";
          to = "export PATH=${runtimePath}:$PATH";
        }
        {
          from = ''source "$HOME/.config/toshy/.venv/bin/activate"'';
          to = "true";
        }
        {
          from = ''xwaykeyz -w -c "$HOME/.config/toshy/toshy_config.py"'';
          to = ''${lib.getExe xwaykeyz} -w -c "''${TOSHY_CONFIG_FILE:-$HOME/.config/toshy/toshy_config.py}"'';
        }
      ];
    }
    {
      files = [ "${toshyShare}/toshy_common/runtime_utils.py" ];
      replacements = [
        {
          from = "home_local_bin = os.path.join(home_dir, '.local', 'bin')";
          to = "home_local_bin = os.environ.get('TOSHY_BIN_DIR') or os.path.join(home_dir, '.local', 'bin')";
        }
        {
          from = "local_site_packages_dir = os.path.join(";
          to = "local_site_packages_dir = os.environ.get('TOSHY_SHARE') or os.path.join(";
        }
      ];
    }
    {
      files = [ "${toshyShare}/toshy_common/terminal_utils.py" ];
      replacements = [
        {
          from = "local_bin = os.path.join(os.path.expanduser('~'), '.local', 'bin')";
          to = "local_bin = os.environ.get('TOSHY_BIN_DIR') or os.path.join(os.path.expanduser('~'), '.local', 'bin')";
        }
        {
          from = "    ('kgx',                     ['-e'],     []                                 ),  # GNOME Console";
          to = lib.concatStringsSep "\n" [
            "    ('kgx',                     ['-e'],     []                                 ),  # GNOME Console"
            "    ('xdg-terminal-exec',       ['--'],     []                                 ),"
          ];
        }
      ];
    }
    {
      files = [ "${toshyShare}/scripts/toshy_versions.py" ];
      replacements = [
        {
          from = "toshy_dir_path          = os.path.join(home_dir, '.config', 'toshy')";
          to = lib.concatStringsSep "\n" [
            "toshy_config_dir_path   = os.environ.get('TOSHY_CONFIG_DIR') or os.path.join(home_dir, '.config', 'toshy')"
            "toshy_dir_path          = os.environ.get('TOSHY_SHARE') or toshy_config_dir_path"
          ];
        }
        {
          from = "if not os.path.exists(toshy_dir_path):";
          to = "if not os.path.exists(toshy_config_dir_path):";
        }
        {
          from = "sys.path.insert(0, toshy_dir_path)";
          to = lib.concatStringsSep "\n" [
            "sys.path.insert(0, toshy_config_dir_path)"
            "sys.path.insert(0, toshy_dir_path)"
          ];
        }
        {
          from = "config_file_path        = os.path.join(toshy_dir_path,";
          to = "config_file_path        = os.path.join(toshy_config_dir_path,";
        }
      ];
    }
    {
      files = [
        "${toshyShare}/default-toshy-config/toshy_config.py"
        "${toshyShare}/default-toshy-config/toshy_config_barebones.py"
      ];
      replacements = [
        {
          from = "icons_dir = os.path.join(home_dir, '.local', 'share', 'icons')";
          to = "icons_dir = os.environ.get('TOSHY_ICONS_DIR') or os.path.join(home_dir, '.local', 'share', 'icons')";
        }
      ];
    }
    {
      files = [ "${toshyShare}/toshy_tray.py" ];
      replacements = [
        {
          from = "    autoload_tray_icon_bool    = widget.get_active()";
          to = lib.concatStringsSep "\n" [
            "    autoload_tray_icon_bool    = widget.get_active()"
            "    if os.environ.get('TOSHY_NIXOS_MODULE'):"
            "        ntfy.send_notification('${nixosAutostartMessage}', icon_file_grayscale)"
            "        return"
          ];
        }
        {
          from = lib.concatStringsSep "\n" [
            "    try:"
            "        if widget.get_active():"
            "            service_manager.enable_services()"
          ];
          to = lib.concatStringsSep "\n" [
            "    if os.environ.get('TOSHY_NIXOS_MODULE'):"
            "        ntfy.send_notification('${nixosModuleMessage}', icon_file_grayscale)"
            "        return"
            ""
            "    try:"
            "        if widget.get_active():"
            "            service_manager.enable_services()"
          ];
        }
        {
          from = "    autostart_toshy_svcs_item.connect(\"toggled\", fn_toggle_toshy_svcs_autostart)";
          to = lib.concatStringsSep "\n" [
            "    if os.environ.get('TOSHY_NIXOS_MODULE'):"
            "        autostart_toshy_svcs_item.set_sensitive(False)"
            "        autostart_toshy_svcs_item.set_tooltip_text('${nixosModuleMessage}')"
            "    autostart_toshy_svcs_item.connect(\"toggled\", fn_toggle_toshy_svcs_autostart)"
          ];
        }
        {
          from = "autoload_tray_icon_item.set_active(cnfg.autoload_tray_icon)";
          to = lib.concatStringsSep "\n" [
            "autoload_tray_icon_item.set_active(cnfg.autoload_tray_icon)"
            "if os.environ.get('TOSHY_NIXOS_MODULE'):"
            "    autoload_tray_icon_item.set_sensitive(False)"
            "    autoload_tray_icon_item.set_tooltip_text('${nixosAutostartMessage}')"
          ];
        }
        {
          from = "tray_dt_file_path           = os.path.join(home_apps_path, tray_dt_file_name)";
          to = "tray_dt_file_path           = os.environ.get('TOSHY_TRAY_DESKTOP_FILE') or os.path.join(home_apps_path, tray_dt_file_name)";
        }
        {
          from = "home_autostart_path         = os.path.join(runtime.home_dir, '.config', 'autostart')";
          to = lib.concatStringsSep "\n" [
            "home_autostart_path         = os.path.join(runtime.home_dir, '.config', 'autostart')"
            "    os.makedirs(home_autostart_path, exist_ok=True)"
          ];
        }
      ];
    }
    {
      files = [ "${toshyShare}/toshy_gui/gui/tools_panel.py" ];
      replacements = [
        {
          from = lib.concatStringsSep "\n" [
            "import shutil"
            "import subprocess"
          ];
          to = lib.concatStringsSep "\n" [
            "import os"
            "import shutil"
            "import subprocess"
          ];
        }
        {
          from = ''debug(f"Autoload tray icon changed to: {new_value}")'';
          to = lib.concatStringsSep "\n" [
            ''debug(f"Autoload tray icon changed to: {new_value}")''
            "        if os.environ.get('TOSHY_NIXOS_MODULE'):"
            "            self.ntfy.send_notification('${nixosAutostartMessage}')"
            "            return"
          ];
        }
        {
          from = ''debug(f"Autostart services changed to: {new_value}")'';
          to = lib.concatStringsSep "\n" [
            ''debug(f"Autostart services changed to: {new_value}")''
            "        if os.environ.get('TOSHY_NIXOS_MODULE'):"
            "            self.ntfy.send_notification('${nixosModuleMessage}')"
            "            return"
          ];
        }
        {
          from = ''self.autostart_services_checkbox.set_tooltip_text("Enable/disable Toshy services to start automatically at login")'';
          to = lib.concatStringsSep "\n" [
            ''self.autostart_services_checkbox.set_tooltip_text("Enable/disable Toshy services to start automatically at login")''
            "            if os.environ.get('TOSHY_NIXOS_MODULE'):"
            "                self.autostart_services_checkbox.set_sensitive(False)"
            "                self.autostart_services_checkbox.set_tooltip_text('${nixosModuleMessage}')"
          ];
        }
        {
          from = "        self.autoload_tray_checkbox.set_active(initial_tray)";
          to = lib.concatStringsSep "\n" [
            "        self.autoload_tray_checkbox.set_active(initial_tray)"
            "        if os.environ.get('TOSHY_NIXOS_MODULE'):"
            "            self.autoload_tray_checkbox.set_sensitive(False)"
            "            self.autoload_tray_checkbox.set_tooltip_text('${nixosAutostartMessage}')"
          ];
        }
        {
          from = "tray_dt_file_path = os.path.join(home_apps_path, tray_dt_file_name)";
          to = "tray_dt_file_path = os.environ.get('TOSHY_TRAY_DESKTOP_FILE') or os.path.join(home_apps_path, tray_dt_file_name)";
        }
        {
          from = "home_autostart_path = os.path.join(self.runtime.home_dir, '.config', 'autostart')";
          to = lib.concatStringsSep "\n" [
            "home_autostart_path = os.path.join(self.runtime.home_dir, '.config', 'autostart')"
            "        os.makedirs(home_autostart_path, exist_ok=True)"
          ];
        }
      ];
    }
    {
      files = [ "${toshyShare}/toshy_layout_selector.py" ];
      replacements = [
        {
          from = "xkb_config_path = '/usr/share/X11/xkb/rules/evdev.xml'";
          to = "xkb_config_path = os.path.join(os.environ.get('XKB_CONFIG_ROOT', '${xkeyboard-config}/share/X11/xkb'), 'rules', 'evdev.xml')";
        }
      ];
    }
    {
      files = [ "${toshyShare}/scripts/toshy-kwin-script-kickstart.sh" ];
      replacements = [
        {
          from = ''icon_file="''${HOME}/.local/share/icons/toshy_app_icon_rainbow.svg"'';
          to = ''icon_file="''${TOSHY_ICONS_DIR:-''${HOME}/.local/share/icons}/toshy_app_icon_rainbow.svg"'';
        }
      ];
    }
    {
      files = [ "${toshyShare}/toshy_common/kblayout_detect/kbld_backend_x11.py" ];
      replacements = [
        {
          from = "ctypes.util.find_library('X11') or 'libX11.so.6'";
          to = "'${lib.getLib libx11}/lib/libX11.so.6'";
        }
      ];
    }
    {
      files = [ "${toshyShare}/toshy_common/kblayout_detect_DEPRECATED.py" ];
      replacements = [
        {
          from = "ctypes.util.find_library('X11') or 'libX11.so.6'";
          to = "'${lib.getLib libx11}/lib/libX11.so.6'";
        }
      ];
    }
    {
      files = [ "${toshyShare}/kwin-dbus-service/toshy_kwin_script_setup.py" ];
      replacements = [
        {
          from = "os.path.join(home_dir, '.config', 'toshy', 'scripts', kickstart_script)";
          to = "os.path.join('${outputPath}/share/toshy/scripts', kickstart_script)";
        }
      ];
    }
    {
      files = [ "${toshyShare}/kwin-dbus-service/org.toshy.Toshy.service" ];
      replacements = [
        {
          from = "Exec=/bin/sh -c";
          to = "Exec=${runtimeShell} -c";
        }
      ];
    }
    {
      files = [ "${toshyShare}/wlroots-dbus-service/toshy_wlroots_dbus_service.py" ];
      replacements = [
        {
          from = "os.path.join(home_dir, '.config', 'toshy', 'scripts', kickstart_script)";
          to = "os.path.join('${outputPath}/share/toshy/scripts', kickstart_script)";
        }
      ];
    }
  ];

}
