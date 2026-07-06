{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.services.toshy;

  allowedUsersFile = pkgs.writeText "toshy-users" (lib.concatLines cfg.users);

  gnomeFocusProviderPackages = {
    inherit (pkgs.gnomeExtensions)
      focused-window-d-bus
      window-calls-extended
      xremap
      ;
  };

  gnomeExtensionPackages = [
    pkgs.gnomeExtensions.appindicator
    gnomeFocusProviderPackages.${cfg.gnomeFocusProvider}
  ];

  sessionVariables = cfg.package.passthru.sessionVariables or pkgs.toshy.passthru.sessionVariables;

  libinputDwtQuirk = ''
    [XWayKeyz Virtual Keyboard]
    MatchUdevType=keyboard
    MatchName=*(virtual) Keyboard
    AttrKeyboardIntegration=internal
  '';

  hardening = {
    CapabilityBoundingSet = [ "" ];
    LockPersonality = true;
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    RestrictAddressFamilies = [ "AF_UNIX" ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    SystemCallArchitectures = [ "native" ];
    UMask = "0077";
  };

  xdgSessionTypeGuard = utils.escapeSystemdExecArgs [
    pkgs.runtimeShell
    "-c"
    ''if [ -z "$XDG_SESSION_TYPE" ]; then sleep 3; exit 1; fi''
  ];

  dbusUnitConfig = {
    StartLimitBurst = 5;
    StartLimitIntervalSec = 60;
  };

  mkToshyService =
    name:
    {
      description,
      program,
      serviceName ? name,
      after ? [ ],
      execStartPre ? [ ],
      restart ? "on-failure",
      unitConfig ? { },
    }:
    {
      inherit description;
      inherit unitConfig;
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [
        "graphical-session.target"
        "systemd-tmpfiles-setup.service"
      ]
      ++ after;
      serviceConfig =
        hardening
        // {
          ExecCondition = "${lib.getExe pkgs.gnugrep} -qxF -- %u ${allowedUsersFile}";
          ExecStart = lib.getExe' cfg.package program;
          Restart = restart;
          RestartSec = "5s";
          SyslogIdentifier = serviceName;
        }
        // lib.optionalAttrs (execStartPre != [ ]) {
          ExecStartPre = execStartPre;
        };
      environment.TERM = "xterm";
    };

  mkTmpfiles =
    user:
    let
      userConfig = config.users.users.${user};
      common = {
        inherit (userConfig) group;
        inherit user;
      };
    in
    {
      "${userConfig.home}/.config".d = common // {
        mode = "0700";
      };
      "${userConfig.home}/.config/toshy".d = common // {
        mode = "0700";
      };
      "${userConfig.home}/.config/toshy/toshy_config.py".C = common // {
        mode = "0600";
        argument = "${cfg.package}/share/toshy/default-toshy-config/toshy_config.py";
      };
    };

  dbusServiceConfig = {
    execStartPre = [ xdgSessionTypeGuard ];
    unitConfig = dbusUnitConfig;
  };

  dbusServices = {
    toshy-kwin-dbus = dbusServiceConfig // {
      description = "Toshy KWin D-Bus Service";
      program = "toshy-kwin-dbus-service";
    };
    toshy-cosmic-dbus = dbusServiceConfig // {
      description = "Toshy COSMIC D-Bus Service";
      program = "toshy-cosmic-dbus-service";
    };
    toshy-wlroots-dbus = dbusServiceConfig // {
      description = "Toshy wlroots D-Bus Service";
      program = "toshy-wlroots-dbus-service";
    };
  };

  toshyServices = {
    toshy-config = {
      description = "Toshy Config Service";
      program = "toshy-config";
      restart = "always";
    };

    toshy-session-monitor = {
      description = "Toshy Session Monitor";
      serviceName = "toshy-sessmon";
      program = "toshy-session-monitor";
      after = [ "toshy-config.service" ];
      restart = "always";
    };
  }
  // lib.optionalAttrs cfg.enableTray {
    toshy-tray = {
      description = "Toshy Tray Indicator";
      program = "toshy-tray";
      after = [ "toshy-config.service" ];
    };
  }
  // dbusServices;
in
{
  options.services.toshy = {
    enable = lib.mkEnableOption "Toshy, a desktop key remapper for Linux that makes shortcuts behave like macOS";

    package = lib.mkPackageOption pkgs "toshy" { };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ ];
      example = [
        "alice"
        "bob"
      ];
      description = ''
        Users allowed to run Toshy.

        These users are added to the `input` and `uinput` groups, which
        grants permission to read input devices and synthesize input events.
      '';
    };

    enableTray = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to start the Toshy tray indicator in graphical sessions.";
    };

    enableGnomeExtensions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to install GNOME Shell extensions for Toshy when
        {option}`services.desktopManager.gnome.enable` is enabled.

        This installs a focused-window D-Bus extension for app-specific
        remapping on GNOME Wayland and AppIndicator support for the tray
        indicator. Users still control whether GNOME Shell enables the
        installed extensions.
      '';
    };

    gnomeFocusProvider = lib.mkOption {
      type = lib.types.enum (builtins.attrNames gnomeFocusProviderPackages);
      default = "focused-window-d-bus";
      example = "window-calls-extended";
      description = ''
        GNOME Shell extension to install as Toshy's focused-window context
        provider.

        Toshy only needs one focused-window provider on GNOME Wayland. The
        default supports modern GNOME releases; `window-calls-extended` and
        `xremap` are available for users who prefer those providers or need
        compatibility with older GNOME releases.
      '';
    };

    enableLibinputDwtQuirk = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to install Toshy's libinput quirk for the xwaykeyz virtual
        keyboard.

        This marks the virtual keyboard as internal so libinput's
        disable-while-typing behavior can still work for touchpads while Toshy
        is active.
      '';
    };

    hidAppleFnmode = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          0
          1
          2
          3
        ]
      );
      default = null;
      example = 2;
      description = ''
        Optional `hid_apple.fnmode` value to persist through
        {option}`boot.extraModprobeConfig`.

        Set to `0` to disable Fn handling, `1` for media keys first, `2` for
        function keys first, or `3` for the kernel's automatic mode.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.users != [ ];
        message = "Toshy requires at least one user in `services.toshy.users`.";
      }
      {
        assertion = lib.all (user: builtins.hasAttr user config.users.users) cfg.users;
        message = "Every user in `services.toshy.users` must be declared in `users.users`.";
      }
    ];

    environment.systemPackages = [
      cfg.package
    ]
    ++ lib.optionals (
      cfg.enableGnomeExtensions && config.services.desktopManager.gnome.enable
    ) gnomeExtensionPackages;

    hardware.uinput.enable = true;

    boot.extraModprobeConfig = lib.mkIf (
      cfg.hidAppleFnmode != null
    ) "options hid_apple fnmode=${toString cfg.hidAppleFnmode}";

    environment.etc = lib.mkIf cfg.enableLibinputDwtQuirk {
      "libinput/local-overrides.quirks".text = lib.mkDefault libinputDwtQuirk;
    };

    users.groups =
      lib.genAttrs
        [
          "input"
          "uinput"
        ]
        (_: {
          members = cfg.users;
        });

    systemd.tmpfiles.settings.toshy = lib.mkMerge (map mkTmpfiles cfg.users);

    services.xserver.displayManager.importedVariables = sessionVariables;

    systemd.user.services = lib.mapAttrs mkToshyService toshyServices;
  };

  meta.maintainers = with lib.maintainers; [ _4evy ];
}
