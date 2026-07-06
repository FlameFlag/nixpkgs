{
  lib,
  pythonEnv,
  runtimePath,
  runtimeShell,
  systemd,
  xkeyboard-config,
  xwaykeyz,
  nixosModuleMessage,
}:

let
  outputPath = placeholder "out";
  toshyShare = "${outputPath}/share/toshy";

  runtimeEnvironment = {
    TOSHY_BIN_DIR = "${outputPath}/bin";
    TOSHY_ICONS_DIR = "${outputPath}/share/icons/hicolor/scalable/apps";
    TOSHY_NIXOS_MODULE = "1";
    TOSHY_SHARE = toshyShare;
    TOSHY_TRAY_DESKTOP_FILE = "${outputPath}/share/applications/Toshy_Tray.desktop";
    XKB_CONFIG_ROOT = "${xkeyboard-config}/share/X11/xkb";
  };

  pythonPrograms = {
    toshy-gui = "-m toshy_gui";
    toshy-tray = "${toshyShare}/toshy_tray.py";
    toshy-env = "${toshyShare}/toshy_common/env_context.py";
    toshy-machine-id = "${toshyShare}/toshy_common/machine_context.py";
    toshy-versions = "${toshyShare}/scripts/toshy_versions.py";
    toshy-xkb-check = "${toshyShare}/toshy_common/xkb_check.py";
    toshy-kblayout-check = "-m toshy_common.kblayout_context";
  };

  scriptWrappers = {
    toshy-config = "${toshyShare}/scripts/tshysvc-config";
    toshy-session-monitor = "${toshyShare}/scripts/tshysvc-sessmon";
    toshy-services-start = "${toshyShare}/scripts/bin/toshy-services-start.sh";
    toshy-services-stop = "${toshyShare}/scripts/bin/toshy-services-stop.sh";
    toshy-services-restart = "${toshyShare}/scripts/bin/toshy-services-restart.sh";
    toshy-services-status = "${toshyShare}/scripts/bin/toshy-services-status.sh";
    toshy-services-log = "${toshyShare}/scripts/bin/toshy-services-log.sh";
  };

  systemctlWrappers = {
    toshy-config-start = "start toshy-config.service";
    toshy-config-stop = "stop toshy-config.service";
    toshy-config-restart = "restart toshy-config.service";
  };

  xwaykeyzWrappers = {
    toshy-devices = "--list-devices";
  };

  moduleManagedCommands = [
    "toshy-services-enable"
    "toshy-services-disable"
    "toshy-systemd-setup"
    "toshy-systemd-setup-debug"
    "toshy-systemd-remove"
  ];

  aliases = {
    toshy-config-verbose-start = "toshy-config-start-verbose";
    toshy-debug = "toshy-config-start-verbose";
  };

  dbusWrappers = [
    {
      name = "toshy-kwin-dbus-service";
      processName = "toshy_kwin_dbus_service";
      target = "kwin-dbus-service/toshy_kwin_dbus_service.py";
      preExec = ''
        nohup ${pythonEnv.interpreter} -u "''${TOSHY_SHARE}/kwin-dbus-service/toshy_kwin_script_setup.py" >/dev/null 2>&1 &
      '';
    }
    {
      name = "toshy-cosmic-dbus-service";
      processName = "toshy_cosmic_dbus_service";
      target = "cosmic-dbus-service/toshy_cosmic_dbus_service.py";
    }
    {
      name = "toshy-wlroots-dbus-service";
      processName = "toshy_wlroots_dbus_service";
      target = "wlroots-dbus-service/toshy_wlroots_dbus_service.py";
    }
  ];

  makePythonWrapper = name: target: ''
    makeWrapper ${pythonEnv.interpreter} $out/bin/${name} \
      "''${gappsWrapperArgs[@]}" \
      "''${toshyRuntimeWrapperArgs[@]}" \
      --prefix PATH : "${runtimePath}" \
      --prefix PYTHONPATH : "${toshyShare}" \
      --add-flags "${target}"
  '';

  makeDbusWrapper =
    {
      name,
      processName,
      target,
      preExec ? "",
    }:
    ''
      makeShellWrapper ${runtimeShell} $out/bin/${name} \
        "''${gappsWrapperArgs[@]}" \
        "''${toshyRuntimeWrapperArgs[@]}" \
        --set TOSHY_SHARE "${toshyShare}" \
        --prefix PATH : "${runtimePath}" \
        --prefix PYTHONPATH : "${toshyShare}" \
        --add-flag "-c" \
        --add-flag ${lib.escapeShellArg ''
          pkill -f ${processName} || true
          sleep 0.5
          ${preExec}
          exec ${pythonEnv.interpreter} -u "''${TOSHY_SHARE}/${target}"
        ''}
    '';

  makeScriptWrapper = name: target: ''
    makeShellWrapper ${runtimeShell} $out/bin/${name} \
      "''${gappsWrapperArgs[@]}" \
      "''${toshyRuntimeWrapperArgs[@]}" \
      --prefix PATH : "${runtimePath}" \
      --prefix PYTHONPATH : "${toshyShare}" \
      --add-flag "${target}"
  '';

  makeSystemctlWrapper = name: args: ''
    makeWrapper ${lib.getExe' systemd "systemctl"} $out/bin/${name} \
      --add-flags "--user ${args}"
  '';

  makeXwaykeyzWrapper = name: flags: ''
    makeWrapper ${lib.getExe xwaykeyz} $out/bin/${name} \
      --prefix PATH : "${runtimePath}" \
      --add-flags "${flags}"
  '';

  makeModuleManagedCommand = program: ''
    makeShellWrapper ${runtimeShell} $out/bin/${program} \
      --add-flag "-c" \
      --add-flag "echo '${nixosModuleMessage}'"
  '';

  makeVerboseConfigRunner = ''
    makeShellWrapper ${runtimeShell} $out/bin/toshy-config-start-verbose \
      "''${gappsWrapperArgs[@]}" \
      "''${toshyRuntimeWrapperArgs[@]}" \
      --prefix PATH : "${runtimePath}" \
      --prefix PYTHONPATH : "${toshyShare}" \
      --add-flag "-c" \
      --add-flag ${lib.escapeShellArg ''
        systemctl --user stop toshy-config.service >/dev/null 2>&1 || true
        pkill -f 'bin/xwaykeyz' || true
        pkill -f 'bin/keyszer' || true
        pkill -f 'bin/xkeysnail' || true

        if command -v xhost >/dev/null 2>&1 && [ "''${XDG_SESSION_TYPE:-}" = x11 ]; then
          xhost +local:
        fi

        exec ${lib.getExe xwaykeyz} --flush -w -v -c "''${TOSHY_CONFIG_FILE:-''${HOME}/.config/toshy/toshy_config.py}"
      ''}
  '';

  makeAlias = name: target: ''
    ln -s ${target} $out/bin/${name}
  '';

  installCommands = [
    ''
      toshyRuntimeWrapperArgs=(
      ${lib.concatMapAttrsStringSep "\n" (
        name: value:
        "  ${lib.escapeShellArgs [
            "--set-default"
            name
            value
          ]}"
      ) runtimeEnvironment}
      )
    ''
    makeVerboseConfigRunner
  ]
  ++ lib.mapAttrsToList makePythonWrapper pythonPrograms
  ++ map makeDbusWrapper dbusWrappers
  ++ lib.mapAttrsToList makeScriptWrapper scriptWrappers
  ++ lib.mapAttrsToList makeSystemctlWrapper systemctlWrappers
  ++ lib.mapAttrsToList makeXwaykeyzWrapper xwaykeyzWrappers
  ++ map makeModuleManagedCommand moduleManagedCommands
  ++ lib.mapAttrsToList makeAlias aliases;
in
{
  checkedPrograms =
    builtins.attrNames pythonPrograms
    ++ builtins.attrNames scriptWrappers
    ++ builtins.attrNames systemctlWrappers
    ++ builtins.attrNames xwaykeyzWrappers
    ++ moduleManagedCommands
    ++ map (wrapper: wrapper.name) dbusWrappers
    ++ builtins.attrNames aliases
    ++ [
      "toshy-config-start-verbose"
    ];

  installCommands = lib.concatStringsSep "\n" installCommands;
}
