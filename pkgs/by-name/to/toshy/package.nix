{
  lib,
  stdenvNoCC,
  copyDesktopItems,
  fetchFromGitHub,
  makeDesktopItem,
  makeWrapper,
  nix-update-script,
  nixosTests,
  wrapGAppsHook4,
  python3Packages,
  coreutils,
  dbus,
  gawk,
  glib,
  gnugrep,
  gnused,
  gtk3,
  gtk4,
  kdePackages,
  libx11,
  libadwaita,
  libayatana-appindicator,
  libnotify,
  procps,
  runtimeShell,
  runtimeShellPackage,
  setxkbmap,
  systemd,
  xdg-terminal-exec,
  xdg-utils,
  xhost,
  xkeyboard-config,
  xset,
  zenity,
}:

let
  outputPath = placeholder "out";
  toshyShare = "${outputPath}/share/toshy";
  iconsDir = "${outputPath}/share/icons/hicolor/scalable/apps";

  xwaykeyz = python3Packages.xwaykeyz;

  pythonDependencies = with python3Packages; [
    dbus-python
    lockfile
    pillow
    psutil
    pygobject3
    pywayland
    sv-ttk
    systemd-python
    tkinter
    watchdog
    xkbcommon
    xwaykeyz
  ];

  pythonEnv = python3Packages.python.withPackages (_: pythonDependencies);

  runtimePath = lib.makeBinPath [
    coreutils
    dbus
    gawk
    glib
    gnugrep
    gnused
    kdePackages.kconfig
    kdePackages.kpackage
    libnotify
    procps
    runtimeShellPackage
    setxkbmap
    systemd
    xdg-terminal-exec
    xdg-utils
    xhost
    xset
    zenity
    xwaykeyz
  ];

  nixosModuleMessage = "Toshy systemd services are managed by the NixOS services.toshy module.";
  nixosAutostartMessage = "Toshy autostart is managed by the NixOS services.toshy module.";

  mkSubstituteArgs =
    replacements:
    lib.concatMapStringsSep " \\\n" (
      { from, to }:
      "--replace-fail ${
        lib.escapeShellArgs [
          from
          to
        ]
      }"
    ) replacements;

  mkSubstitution =
    {
      files,
      replacements,
    }:
    ''
      substituteInPlace ${lib.escapeShellArgs files} \
      ${mkSubstituteArgs replacements}
    '';

  wrapper = import ./wrapper.nix {
    inherit
      lib
      pythonEnv
      runtimePath
      runtimeShell
      systemd
      xkeyboard-config
      xwaykeyz
      nixosModuleMessage
      ;
  };

  packageData = import ./data.nix {
    inherit
      lib
      outputPath
      runtimeShell
      toshyShare
      runtimePath
      libx11
      xkeyboard-config
      xwaykeyz
      nixosModuleMessage
      nixosAutostartMessage
      ;
  };

  inherit (packageData)
    iconNames
    runtimeScripts
    sessionVariables
    substitutions
    toshyFiles
    ;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "toshy";
  version = "26.06.0";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "RedBearAK";
    repo = "Toshy";
    tag = "Toshy_v${finalAttrs.version}";
    hash = "sha256-zFdS5YpGVxkMhhTtAi0iX6ilc+xRw8xWYGtceMjXx9w=";
  };

  nativeBuildInputs = [
    copyDesktopItems
    makeWrapper
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk3
    gtk4
    libadwaita
    libayatana-appindicator
    pythonEnv # So patchShebangs finds the same Python environment used by wrappers.
    runtimeShellPackage # So patchShebangs finds a bash suitable for installed scripts.
  ];

  dontWrapGApps = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p ${
      lib.escapeShellArgs [
        toshyShare
        "${outputPath}/bin"
        iconsDir
      ]
    }

    cp -r ${lib.escapeShellArgs toshyFiles} ${lib.escapeShellArg "${toshyShare}/"}

    ${lib.concatLines (
      map (
        script:
        "install -Dm755 ${
          lib.escapeShellArgs [
            script
            "${toshyShare}/${script}"
          ]
        }"
      ) runtimeScripts
    )}

    ${lib.concatLines (
      map (
        icon:
        "install -Dm644 ${
          lib.escapeShellArgs [
            "assets/${icon}.svg"
            "${iconsDir}/${icon}.svg"
          ]
        }"
      ) iconNames
    )}

    ${lib.concatLines (map mkSubstitution substitutions)}

    patchShebangs --host ${lib.escapeShellArg toshyShare}

    ${wrapper.installCommands}

    runHook postInstall
  '';

  doInstallCheck = true;

  desktopItems = [
    (makeDesktopItem {
      name = "app.toshy.preferences";
      desktopName = "Toshy Preferences";
      genericName = "Toshy Preferences";
      startupWMClass = "app.toshy.preferences";
      exec = "toshy-gui";
      icon = "toshy_app_icon_rainbow";
      comment = "Preferences GUI for Toshy. Make Linux work like a 'Tosh!";
      categories = [ "Utility" ];
    })
    (makeDesktopItem {
      name = "Toshy_Tray";
      desktopName = "Toshy Tray Icon";
      genericName = "Toshy Tray Icon";
      exec = "toshy-tray";
      icon = "toshy_app_icon_rainbow";
      comment = "Tray Icon Menu for Toshy. Make Linux work like a 'Tosh!";
      categories = [ "Utility" ];
    })
  ];

  installCheckPhase = ''
    runHook preInstallCheck

    ${lib.concatMapStringsSep "\n" (
      program: "test -x ${lib.escapeShellArg "${outputPath}/bin/${program}"}"
    ) wrapper.checkedPrograms}

    ${lib.concatMapStringsSep "\n" (
      script: "test -f ${lib.escapeShellArg "${toshyShare}/${script}"}"
    ) runtimeScripts}

    printf '%s\n' ${lib.escapeShellArgs runtimeScripts} > expected-toshy-scripts
    (cd ${lib.escapeShellArg toshyShare} && find scripts -type f | sort) > actual-toshy-scripts
    diff -u expected-toshy-scripts actual-toshy-scripts

    if find ${lib.escapeShellArg toshyShare} -type f -perm -0100 -exec grep -Il '^#! */usr/bin' {} + | grep -q .; then
      echo "found unpatched FHS shebangs in installed Toshy files" >&2
      find ${lib.escapeShellArg toshyShare} -type f -perm -0100 -exec grep -Il '^#! */usr/bin' {} +
      exit 1
    fi

    grep -qF "Exec=toshy-gui" ${lib.escapeShellArg "${outputPath}/share/applications/app.toshy.preferences.desktop"}
    grep -qF "Exec=toshy-tray" ${lib.escapeShellArg "${outputPath}/share/applications/Toshy_Tray.desktop"}

    ${pythonEnv.interpreter} - ${lib.escapeShellArg toshyShare} <<'PY'
    import pathlib
    import sys

    for path in pathlib.Path(sys.argv[1]).rglob("*.py"):
        compile(path.read_text(), str(path), "exec")
    PY
    PYTHONPATH=${lib.escapeShellArg toshyShare} ${pythonEnv.interpreter} - <<'PY'
    import importlib

    for module in [
        "toshy_common.env_context",
        "toshy_common.notification_manager",
        "toshy_common.process_manager",
        "toshy_common.runtime_utils",
        "toshy_common.service_manager",
        "toshy_common.terminal_utils",
    ]:
        importlib.import_module(module)
    PY
    test -x "${lib.getExe' kdePackages.kpackage "kpackagetool6"}"
    test -x "${lib.getExe' kdePackages.kconfig "kwriteconfig6"}"
    test -f ${lib.escapeShellArg "${toshyShare}/kwin-script/kde5_kde6_merged/toshy-dbus-notifyactivewindow/contents/code/main.js"}

    runHook postInstallCheck
  '';

  passthru = {
    tests = {
      inherit (nixosTests) toshy;
    };
    updateScript = nix-update-script {
      extraArgs = [ "--version-regex=^Toshy_v(\\d+\\.\\d+\\.\\d+)$" ];
    };
    inherit
      sessionVariables
      xwaykeyz
      ;
    inherit (wrapper) checkedPrograms;
  };

  meta = {
    changelog = "https://github.com/RedBearAK/Toshy/releases/tag/${finalAttrs.src.tag}";
    description = "Desktop key remapper for Linux that makes shortcuts behave like macOS";
    homepage = "https://github.com/RedBearAK/Toshy";
    license = lib.licenses.gpl3Plus;
    mainProgram = "toshy-gui";
    maintainers = with lib.maintainers; [ _4evy ];
    platforms = lib.platforms.linux;
  };
})
