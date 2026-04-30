{
  lib,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  pkg-config,
  protobuf,
  fontconfig,
  freetype,
  openssl,
  sqlite,
  zlib,
  zstd,
  glib,
  alsa-lib,
  libxkbcommon,
  wayland,
  libxcb,
  libX11,
  libXext,
  libXi,
  libXcursor,
  libXrandr,
  libGL,
  vulkan-loader,
  apple-sdk_15,
  darwin,
  libicns,
  makeWrapper,
  stdenv,
}:

let
  inherit (stdenv.hostPlatform) isDarwin isLinux;

  # Some build scripts read files outside their crate directories
  # Fetch the full upstream repos so postPatch can add those files to the
  # vendored crates
  warpProtoApisSrc = fetchFromGitHub {
    owner = "warpdotdev";
    repo = "warp-proto-apis";
    rev = "3dd0cd81eae83b4ce09c7805c8ef12599798aa26";
    hash = "sha256-qN7dw/EH0ftbpDsAmyNmvgYb8FWGRRig4AYHQqgxByg=";
  };
  warpWorkflowsHash =
    if isDarwin then
      "sha256-yRTtgiNpYjpQWHhqGSm9qP7zUtQhuxZfee2ThWRVR/A="
    else
      "sha256-ICgkxlUUIfyhr0agZEk3KtGHX0uNRlRCKtz0iF2jd7o=";
  warpWorkflowsSrc = fetchFromGitHub {
    owner = "warpdotdev";
    repo = "workflows";
    rev = "793a98ddda6ef19682aed66364faebd2829f0e01";
    hash = warpWorkflowsHash;
  };

  toPlist = lib.generators.toPlist { escape = true; };
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "warp-terminal";
  version = "0.2026.05.11.09.24.dev_00";

  src = fetchFromGitHub {
    owner = "warpdotdev";
    repo = "warp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-65JDbizveKUgM7ChwRzinY2i5RDraMvxCLeLO5jRNTA=";
    fetchLFS = true;
  };

  cargoHash = "sha256-OMiZzZ3bYHOBGqrE25nod6GkjDC1A127rZiUQgQbxhs=";

  # cargo-auditable can wedge while compiling Warp's main crate.
  auditable = false;

  postPatch = ''
    # Upstream's rustflags include a macOS linker flag and a nightly-only symbol
    # mangling setting
    rm .cargo/config.toml

    # This build script expects the proto files above the crate directory
    warpMultiAgentApiDir=$(find "$cargoDepsCopy" -type d -name 'warp_multi_agent_api-0.0.0' -print -quit)
    cp ${warpProtoApisSrc}/apis/multi_agent/v1/*.proto "$warpMultiAgentApiDir/"
    substituteInPlace "$warpMultiAgentApiDir/build.rs" \
      --replace-fail \
        'manifest_dir.parent().unwrap().parent().unwrap()' \
        'manifest_dir.as_path()'

    # This build script expects ../specs from the upstream repo layout
    warpWorkflowsDir=$(find "$cargoDepsCopy" -type d -name 'warp-workflows-0.1.0' -print -quit)
    cp -r ${warpWorkflowsSrc}/specs "$warpWorkflowsDir/specs"
    substituteInPlace "$warpWorkflowsDir/build.rs" \
      --replace-fail '../specs' 'specs'
  ''
  + lib.optionalString isDarwin ''
    # Avoid the upstream universal build flags.
    substituteInPlace app/DockTilePlugin/Makefile \
      --replace-fail '-arch arm64 -arch x86_64' '-arch ${stdenv.hostPlatform.darwinArch}'

    # Nix cannot provide Apple's Metal compiler. Use the checked-in metallib.
    install -Dm644 ${./shaders.metallib} crates/warpui/shaders.metallib
    patch -p1 < ${./patches/0001-warpui-use-prebuilt-metallib.patch}
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    protobuf
    rustPlatform.bindgenHook
  ]
  ++ lib.optionals isDarwin [
    darwin.autoSignDarwinBinariesHook
    libicns
    makeWrapper
  ];

  dontUseCmakeConfigure = true;

  buildInputs = [
    fontconfig
    freetype
    openssl
    sqlite
    zlib
    zstd
  ]
  ++ lib.optionals isLinux [
    glib
    alsa-lib
    libxkbcommon
    wayland
    libxcb
    libX11
    libXext
    libXi
    libXcursor
    libXrandr
  ]
  ++ lib.optionals isDarwin [
    apple-sdk_15
  ];

  cargoBuildFlags = [
    "--bin"
    "warp-oss"
  ];

  buildFeatures = [
    "release_bundle"
    "gui"
    "nld_improvements"
  ];

  doCheck = false;

  env = {
    OPENSSL_NO_VENDOR = true;
    LIBSQLITE3_SYS_USE_PKG_CONFIG = true;
    ZSTD_SYS_USE_PKG_CONFIG = true;
  }
  // lib.optionalAttrs isDarwin {
    # app/build.rs expects this on macOS
    MACOSX_DEPLOYMENT_TARGET = "10.14";
  };

  installPhase =
    if isDarwin then
      ''
        runHook preInstall

        binary="target/${stdenv.hostPlatform.rust.cargoShortTarget}/release/warp-oss"

        # app/build.rs does not account for --target when placing the plugin.
        plugin=$(find target -type d -name 'WarpDockTilePlugin.docktileplugin' -print -quit)
        if [ -z "$plugin" ]; then
          echo "ERROR: WarpDockTilePlugin.docktileplugin not produced by the build" >&2
          exit 1
        fi

        app="$out/Applications/WarpOss.app"
        mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/PlugIns"

        install -m 755 "$binary" "$app/Contents/MacOS/warp-oss"
        cp -R "$plugin" "$app/Contents/PlugIns/"

        iconset=$(mktemp -d)
        cp app/channels/oss/icon/no-padding/512x512.png "$iconset/AppIcon_512x512.png"
        png2icns "$app/Contents/Resources/AppIcon.icns" "$iconset/AppIcon_512x512.png"

        printf '%s' ${
          lib.escapeShellArg (toPlist (import ./info-plist.nix { inherit (finalAttrs) version; }))
        } > "$app/Contents/Info.plist"

        mkdir -p "$out/bin"
        makeWrapper "$app/Contents/MacOS/warp-oss" "$out/bin/warp-terminal-oss"
        ln -s warp-terminal-oss "$out/bin/warp-terminal"

        runHook postInstall
      ''
    else
      ''
        runHook preInstall

        install -Dm755 \
          target/${stdenv.hostPlatform.rust.cargoShortTarget}/release/warp-oss \
          $out/bin/warp-terminal-oss
        ln -s warp-terminal-oss $out/bin/warp-terminal

        install -Dm644 \
          app/channels/oss/dev.warp.WarpOss.desktop \
          $out/share/applications/dev.warp.WarpOss.desktop

        install -Dm644 \
          app/channels/oss/icon/no-padding/512x512.png \
          $out/share/icons/hicolor/512x512/apps/dev.warp.WarpOss.png

        runHook postInstall
      '';

  postFixup = lib.optionalString isLinux ''
    patchelf $out/bin/warp-terminal-oss \
      --add-rpath ${
        lib.makeLibraryPath [
          # Loaded with dlopen, so patchelf cannot discover them from NEEDED
          libGL
          libxkbcommon
          vulkan-loader
          wayland
        ]
      }
  '';

  meta = {
    description = "Open-source build of the Warp terminal (warp-oss channel)";
    homepage = "https://github.com/warpdotdev/warp";
    license = with lib.licenses; [
      agpl3Only
      mit
    ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      # Prebuilt Darwin Metal shader library, see patches/0001-warpui-use-prebuilt-metallib.patch.
      binaryNativeCode
    ];
    mainProgram = "warp-terminal";
    maintainers = with lib.maintainers; [
      imadnyc
      FlameFlag
      johnrtitor
      logger
    ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
})
