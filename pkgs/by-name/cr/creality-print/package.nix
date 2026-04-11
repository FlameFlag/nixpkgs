{
  gcc14Stdenv,
  stdenv,
  lib,
  alibabacloud-oss-cpp-sdk,
  binutils,
  fetchFromGitHub,
  cmake,
  pkg-config,
  wrapGAppsHook3,
  boost184,
  cereal,
  cgal_5,
  curl,
  dbus,
  eigen,
  expat,
  ffmpeg,
  gcc-unwrapped,
  glew,
  glfw,
  glib,
  glib-networking,
  gmp,
  gst_all_1,
  gtest,
  gtk3,
  hicolor-icon-theme,
  libsecret,
  libpng,
  mpfr,
  nlopt,
  opencascade-occt_7_6,
  openssl,
  openvdb,
  opencv,
  pcre,
  systemd,
  onetbb,
  webkitgtk_4_1,
  wxwidgets_3_1,
  libx11,
  libnoise,
  assimp,
  paho-mqtt-c,
  paho-mqtt-cpp,
  freetype,
  libdeflate,
  lerc,
  libjpeg,
  x264,
  zstd,
  ccacheStdenv,
  withSystemd ? stdenv.hostPlatform.isLinux,
  # Compile cache survives across rebuilds via /nix/var/cache/ccache.
  # Requires `extra-sandbox-paths = /nix/var/cache/ccache` in nix.conf.
  enableCCache ? true,
}:
let
  # GCC 14 on Linux, AppleClang on Darwin. Upstream's macOS build uses
  # AppleClang and relies on Apple-specific warning flags.
  baseStdenv = if stdenv.hostPlatform.isDarwin then stdenv else gcc14Stdenv;

  stdenv' =
    if enableCCache then
      ccacheStdenv.override {
        stdenv = baseStdenv;
        extraConfig = ''
          export CCACHE_COMPRESS=1
          export CCACHE_DIR=/nix/var/cache/ccache
          export CCACHE_UMASK=007
          # Each nix build has a unique $NIX_BUILD_TOP (e.g.
          # /nix/var/nix/builds/nix-XXXXX-YYY). Without basedir the
          # absolute path is embedded in preprocessed output and every
          # TU hashes differently across builds = 0% hit rate.
          export CCACHE_BASEDIR="$NIX_BUILD_TOP"
          export CCACHE_NOHASHDIR=1
          export CCACHE_SLOPPINESS=pch_defines,time_macros,random_seed,include_file_mtime,include_file_ctime,system_headers,file_macro
          export CCACHE_COMPILERCHECK=content
        '';
      }
    else
      baseStdenv;

  # CrealityPrint expects Boost 1.84; use matching version to avoid
  # API breakage in 1.86+ (removed extension/basename/change_extension/copy_option).
  boost = boost184.override {
    enableShared = true;
    enableStatic = false;
    extraFeatures = [
      "log"
      "thread"
      "filesystem"
    ];
  };

  # Rebuild openvdb against the same Boost to avoid ABI conflicts at link time.
  openvdb' = openvdb.override { boost = boost184; };

  wxGTK' =
    (wxwidgets_3_1.override {
      withCurl = true;
      withPrivateFonts = true;
      withWebKit = true;
      withEGL = false;
    }).overrideAttrs
      (old: {
        buildInputs =
          old.buildInputs
          ++ lib.optionals stdenv.hostPlatform.isLinux [ libsecret ];
        configureFlags =
          old.configureFlags
          ++ [ "--enable-debug=no" ]
          # libsecret-backed secret store is only available on Linux builds.
          ++ lib.optionals stdenv.hostPlatform.isLinux [ "--enable-secretstore" ]
          # Internal Objective-C classes (wxCocoaOutlineView,
          # wxNSCustomOpenGLView) are otherwise hidden; CrealityPrint's
          # MacDarkMode.mm extends them via categories and needs them
          # resolvable at link time.
          ++ lib.optionals stdenv.hostPlatform.isDarwin [ "--disable-visibility" ];
        # wxWidgets' make install omits the `private/` subtree. Upstream
        # CrealityPrint includes <wx/private/jsscriptwrapper.h> on macOS
        # and Windows for WebView JS exec. Ship the private headers so
        # downstream consumers can find them.
        postInstall =
          (old.postInstall or "")
          + ''
            cp -r $src/include/wx/private $out/include/wx-3.1/wx/
          '';
      });
in
stdenv'.mkDerivation (finalAttrs: {
  pname = "creality-print";
  version = "7.1.0-unstable-2025-04-30";

  src = fetchFromGitHub {
    owner = "CrealityOfficial";
    repo = "CrealityPrint";
    rev = "010c71df651cdaf4018b7d3b006f4be9009e3fb9";
    hash = "sha256-HnNZVl6iaxWwrdkPKdiEA/dQreFiKua2PuwogD+ocx8=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    wxGTK'
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ wrapGAppsHook3 ];

  buildInputs = [
    alibabacloud-oss-cpp-sdk
    binutils
    boost
    cereal
    cgal_5
    curl
    eigen
    expat
    ffmpeg
    freetype
    gcc-unwrapped
    glew
    glfw
    glib
    gmp
    libdeflate
    lerc
    libjpeg
    libpng
    mpfr
    nlopt
    opencascade-occt_7_6
    openssl
    openvdb'
    opencv.cxxdev
    pcre
    onetbb
    assimp
    paho-mqtt-c
    paho-mqtt-cpp
    wxGTK'
    x264
    libnoise
  ]
  # GTK/WebKit/GStreamer/D-Bus stack is the GUI backend on Linux only.
  # On Darwin, wxWidgets uses the native Cocoa + WebKit stack.
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    dbus
    glib-networking
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-good
    gtk3
    hicolor-icon-theme
    libsecret
    webkitgtk_4_1
    libx11
  ]
  # Upstream links zstd explicitly only on Apple.
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ zstd ]
  ++ lib.optionals withSystemd [ systemd ]
  ++ finalAttrs.nativeCheckInputs;

  patches = [
    # FindOpenVDB.cmake requires cmake 3.3 (too old for cmake 4.x) and
    # references IlmBase which was removed from modern OpenEXR/Imath.
    ./patches/0001-FindOpenVDB-bump-cmake_minimum_required-to-3.5-and-r.patch

    # CrealityPrint links opencv_world (Windows monolithic build);
    # nixpkgs builds separate modules (opencv_core, opencv_imgproc).
    ./patches/0002-libslic3r-link-opencv_core-and-opencv_imgproc-instea.patch

    # metartc (WebRTC for printer camera) cannot be built from source:
    # it requires older FFmpeg (<6.0) and OpenSSL (<3.0) APIs that are
    # incompatible with current nixpkgs versions. Disable unconditionally.
    ./patches/0003-src-disable-WebRTC-video-unconditionally-metartc-not.patch

    # wxWidgets may be built without filesystem watcher support
    # (wxUSE_FSWATCHER=0). Guard usage with preprocessor checks.
    ./patches/0004-GUI_App-guard-wxFileSystemWatcher-usage-with-wxUSE_F.patch

    # Source files include WebRTCDecoder.h guarded only by __linux__;
    # also need ENABLE_WEBRTC_VIDEO check since the feature is disabled.
    ./patches/0005-src-guard-WebRTCDecoder-usage-with-ENABLE_WEBRTC_VID.patch

    # FromDIP(-1) scales the -1 sentinel through DPI conversion, producing
    # values that violate GTK's width >= -1 assertion. Also guard
    # gtk_cell_layout_get_cells with a GTK_IS_CELL_LAYOUT type check.
    ./patches/0006-src-fix-GTK-widget-sizing-crashes-on-Linux.patch

    # Plater::priv destructor crashes during exception unwinding because
    # it unconditionally accesses main_frame->m_tabpanel which may be null.
    ./patches/0007-Plater-make-destructor-safe-during-exception-unwindi.patch

    # ProfileLoader parses JSON without checking ifstream state or
    # catching parse errors; crashes on empty/missing profile files.
    ./patches/0008-libslic3r-guard-unprotected-JSON-stream-reads-in-Pro.patch

    # wxMediaState is an unscoped enum [0..2]; casting 6 to it fails in
    # constexpr under clang 21 (nixpkgs). AppleClang accepts it silently.
    # Widen to `int` to match the sibling declaration in MediaPlayCtrl.h.
    ./patches/0009-wxMediaCtrl2-widen-MEDIASTATE_BUFFERING-type-for-cla.patch

    # wxWidgets 3.1.7 base declares OnAddBitmap(wxBitmapBundle&); CrealityPrint
    # overrides with wxBitmap&. clang 21 rejects this mismatched `override`
    # as a hard error. Drop the keyword; direct calls still work.
    ./patches/0010-BitmapComboBox-drop-override-on-OnAddBitmap-for-clan.patch

    # macOS Breakpad include is gated only on TARGET_OS_MAC (the
    # USE_BREAKPAD check is commented out upstream). Gate it properly
    # so ENABLE_BREAKPAD=OFF builds don't pull in breakpad headers.
    ./patches/0011-GUI_Init-gate-macOS-Breakpad-block-on-USE_BREAKPAD.patch

    # wxWidgets 3.1.7 renamed wxBitmapComboBoxBase::m_bitmaps to
    # m_bitmapbundles. Use GetBitmapFor(this) to pull a wxBitmap.
    ./patches/0012-BitmapComboBox-use-m_bitmapbundles-wxWidgets-3.1.7-i.patch

    # wxCocoaOutlineView's `implementation` ivar is @private and its
    # OBJC_IVAR symbol isn't exported; use the public accessor instead.
    ./patches/0013-MacDarkMode-use-implementation-accessor-instead-of-p.patch
  ];

  strictDeps = true;

  doCheck = true;
  nativeCheckInputs = [ gtest ];

  separateDebugInfo = stdenv.hostPlatform.isLinux;

  env = {
    NLOPT = nlopt;

    NIX_CFLAGS_COMPILE = toString (
      [
        "-Wno-ignored-attributes"
        "-I${opencv.out}/include/opencv4"
        "-Wno-error=incompatible-pointer-types"
        "-Wno-uninitialized"
        "-Wno-unused-result"
        "-Wno-deprecated-declarations"
        # Clang: downgrade to warnings. These fire on upstream patterns:
        #  - overloaded-virtual: wxWidgets 3.1 bumped some bases to
        #    wxBitmapBundle; Creality still overrides with wxBitmap.
        #  - format-security: nixpkgs hardening sets -Werror=format-security;
        #    Creality passes runtime _L("...") strings to ImGui::Text.
        "-Wno-error=overloaded-virtual"
        "-Wno-error=format-security"
        "-DBOOST_ALLOW_DEPRECATED_HEADERS"
        "-DBOOST_MATH_DISABLE_STD_FPCLASSIFY"
        "-DBOOST_MATH_NO_LONG_DOUBLE_MATH_FUNCTIONS"
        "-DBOOST_MATH_DISABLE_FLOAT128"
        "-DBOOST_MATH_NO_QUAD_SUPPORT"
        "-DBOOST_MATH_MAX_FLOAT128_DIGITS=0"
        "-DBOOST_CSTDFLOAT_NO_LIBQUADMATH_SUPPORT"
        "-DBOOST_MATH_DISABLE_FLOAT128_BUILTIN_FPCLASSIFY"
        "-DBOOST_LOG_DYN_LINK"
      ]
      # GCC-only warning flags. Clang doesn't recognize these.
      ++ lib.optionals stdenv'.cc.isGNU [
        "-Wno-template-id-cdtor"
        "-Wno-use-after-free"
        "-Wno-format-overflow"
        "-Wno-stringop-overflow"
      ]
    );

    NIX_LDFLAGS = toString (
      lib.optionals stdenv.hostPlatform.isLinux [ "-lwebkit2gtk-4.1" ]
      ++ lib.optionals withSystemd [ "-ludev" ]
      # MacDarkMode.mm references WKWebView via a category;
      # upstream's CMake doesn't link WebKit on darwin.
      ++ lib.optionals stdenv.hostPlatform.isDarwin [ "-framework" "WebKit" ]
    );
  };

  prePatch =
    let
      tpmsArchDir =
        if stdenv.hostPlatform.isDarwin then
          "mac/${if stdenv.hostPlatform.isAarch64 then "arm64" else "x86_64"}"
        else
          "linux/x86_64";
    in
    ''
      # Make CR_TPMS prebuilt library findable
      install -Dm644 deps/CR_TPMS/cr_tpms/include/cr_tpms_library.h -t $TMPDIR/cr_tpms/include
      install -Dm644 deps/CR_TPMS/cr_tpms/lib/${tpmsArchDir}/libcr_tpms_library.a -t $TMPDIR/cr_tpms/lib
      export CMAKE_INCLUDE_PATH="$TMPDIR/cr_tpms/include''${CMAKE_INCLUDE_PATH:+:$CMAKE_INCLUDE_PATH}"
      export CMAKE_LIBRARY_PATH="$TMPDIR/cr_tpms/lib''${CMAKE_LIBRARY_PATH:+:$CMAKE_LIBRARY_PATH}"
      export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -isystem $TMPDIR/cr_tpms/include"
    '';

  postPatch = ''
    # Fix nlopt and libnoise lookup
    substituteInPlace cmake/modules/FindNLopt.cmake \
      --replace-fail "nlopt_cxx" "nlopt"
    substituteInPlace src/libslic3r/Feature/FuzzySkin/FuzzySkin.cpp \
      --replace-fail '"libnoise/noise.h"' '"noise/noise.h"'

    # Remove hardcoded OpenCASCADE path
    substituteInPlace src/libslic3r/CMakeLists.txt \
      --replace-fail 'set(OpenCASCADE_DIR "''${CMAKE_PREFIX_PATH}/lib/cmake/occt")' ""

    # Use shared paho-mqtt-cpp instead of static; fix install dir
    substituteInPlace src/CMakeLists.txt \
      --replace-fail "PahoMqttCpp::paho-mqttpp3-static" "PahoMqttCpp::paho-mqttpp3" \
      --replace-fail 'set(CMAKE_INSTALL_BINDIR "./")' ""
  '';

  cmakeFlags = [
    (lib.cmakeBool "SLIC3R_STATIC" false)
    (lib.cmakeBool "SLIC3R_FHS" stdenv.hostPlatform.isLinux)
    (lib.cmakeFeature "SLIC3R_GTK" "3")
    (lib.cmakeBool "BBL_RELEASE_TO_PUBLIC" true)
    (lib.cmakeBool "BBL_INTERNAL_TESTING" false)
    (lib.cmakeBool "SLIC3R_BUILD_TESTS" false)
    (lib.cmakeBool "SLIC3R_PCH" true)
    (lib.cmakeBool "ENABLE_BREAKPAD" false)
    (lib.cmakeFeature "CMAKE_CXX_FLAGS" "-DGL_SILENCE_DEPRECATION")
    (lib.cmakeFeature "CMAKE_INSTALL_BINDIR" "bin")
    (lib.cmakeFeature "LIBNOISE_INCLUDE_DIR" "${libnoise}/include")
    (lib.cmakeFeature "LIBNOISE_LIBRARY_RELEASE" "${libnoise}/lib/libnoise-static.a")
    (lib.cmakeFeature "CMAKE_POLICY_VERSION_MINIMUM" "3.5")
    "-Wno-dev"
  ]
  # GNU ld flag; Apple ld64 doesn't understand --no-as-needed.
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    (lib.cmakeFeature "CMAKE_EXE_LINKER_FLAGS" "-Wl,--no-as-needed")
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    (lib.cmakeBool "CMAKE_MACOSX_BUNDLE" true)
  ];

  preFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : "$out/lib:${
        lib.makeLibraryPath [
          glew
        ]
      }"
      --set WEBKIT_DISABLE_COMPOSITING_MODE 1
    )
  '';

  postInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
    rm -f $out/LICENSE.txt
  '';

  meta = {
    description = "3D printing slicer software by Creality for Creality and other 3D printers";
    homepage = "https://github.com/CrealityOfficial/CrealityPrint";
    license = lib.licenses.agpl3Only;
    mainProgram = "CrealityPrint";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
