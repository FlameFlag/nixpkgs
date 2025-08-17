{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  assimp,
  boost177,
  cereal,
  cgal,
  clipper2,
  curl,
  dbus,
  egl-wayland,
  eigen,
  elfutils,
  breakpad,
  extra-cmake-modules,
  ffmpeg,
  git,
  glew,
  glfw,
  glib,
  gst_all_1,
  gtk2,
  ilmbase,
  lerc,
  libdatrie,
  libepoxy,
  libjpeg,
  libmspack,
  libsecret,
  libselinux,
  libsepol,
  libsysprof-capture,
  libthai,
  libtiff,
  libunwind,
  libxkbcommon,
  makeWrapper,
  mesa,
  mpfr,
  nlopt,
  opencascade-occt,
  opencv,
  openssl,
  openvdb,
  orca-slicer,
  pcre2,
  systemd,
  tbb_2022,
  texinfo,
  util-linux,
  webkitgtk_4_1,
  wrapGAppsHook,
  wxGTK31,
  xorg,
  expat,
  libpng,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "creality-print";
  version = "6.2.1";

  src = fetchFromGitHub {
    owner = "CrealityOfficial";
    repo = "CrealityPrint";
    rev = "v${finalAttrs.version}";
    fetchSubmodules = true;
    hash = "sha256-brvo8itvYLEzgkWjfoX1AVzvimiSutdNrRu7wUdqAg8=";
  };

  # https://github.com/NixOS/nixpkgs/blob/5f3828dd8a0ec558ce66f49533ccd3e44349ab9a/pkgs/by-name/or/orca-slicer/package.nix#L45-L56
  wxGTK' =
    (wxGTK31.override {
      withCurl = true;
      withPrivateFonts = true;
      withWebKit = true;
    }).overrideAttrs
      (old: {
        configureFlags = old.configureFlags ++ [ "--enable-debug=no" ];
      });

  nativeBuildInputs = [
    cmake
    pkg-config
    git
    texinfo
  ]
  ++ lib.optionals stdenv.isLinux [
    wrapGAppsHook
    makeWrapper
    extra-cmake-modules
    finalAttrs.wxGTK'
  ];

  buildInputs = [
    libpng
    expat
    assimp
    boost177
    boost177.dev
    cereal
    cgal
    clipper2
    curl
    eigen
    ffmpeg
    glew
    glfw
    glib
    ilmbase
    lerc
    libjpeg
    libtiff
    mpfr
    nlopt
    opencascade-occt
    opencv
    openssl
    openvdb
    pcre2
    tbb_2022
    breakpad
  ]
  ++ lib.optionals stdenv.isLinux [
    orca-slicer
    elfutils
    dbus
    egl-wayland
    gst_all_1.gst-plugins-base
    gst_all_1.gstreamer
    gtk2
    libdatrie
    libepoxy
    libmspack
    libsecret
    libselinux
    libsepol
    libsysprof-capture
    libthai
    libunwind
    libxkbcommon
    mesa
    systemd
    util-linux
    webkitgtk_4_1
    finalAttrs.wxGTK'
    xorg.libXdmcp
    xorg.libXtst
  ];

  postPatch = ''
    sed -i 's/add_subdirectory(package)/#add_subdirectory(package) # Disabled packaging/' CMakeLists.txt
  ''
  + lib.optionalString stdenv.isLinux ''''
  + lib.optionalString stdenv.isDarwin ''
    sed -i 's|option(SLIC3R_STATIC .*)|option(SLIC3R_STATIC "Compile CrealityPrint with static libraries (Boost, TBB, glew)" OFF)|' CMakeLists.txt
    sed -i 's|add_executable(''${PROJECT_DLL} CrealityPrint.cpp|add_executable(''${PROJECT_DLL} MACOSX_BUNDLE CrealityPrint.cpp|' src/CMakeLists.txt
  '';

  enableParallelBuilding = true;

  cmakeFlags = [
    "-DwxWidgets_CONFIG_EXECUTABLE=${finalAttrs.wxGTK'}/bin/wx-config"
    "-DBoost_ROOT=${boost177}"
    "-DOpenCV_DIR=${opencv}/lib/cmake/opencv4"
    "-DOPENCV_INCLUDE_DIRS=${opencv}/include/opencv4"
    "-DLIB_BREAKPAD=${breakpad}/lib/libbreakpad_client.a"
    "DSLIC3R_ENABLE_WEBRTC=OFF"
  ]
  ++ lib.optionals stdenv.isLinux [ "-DSLIC3R_GTK=3" ];

  env.NIX_CFLAGS_COMPILE = toString [
    "-w"
    "-Wno-error"
    "-fpermissive"
    "-fno-strict-aliasing"
    "-Wno-maybe-uninitialized"
    "-Wno-uninitialized"
    "-Wno-template-id-cdtor"
    "-Wno-unused-function"
    "-Wno-unused-variable"
    "-Wno-sign-compare"
    "-Wno-unused-but-set-variable"
    "-Wno-subobject-linkage"
    "-Wno-pessimizing-move"
    "-Wno-dangling-else"
    "-Wno-range-loop-construct"
    "-Wno-overflow"
    "-Wno-array-bounds"
    "-Wno-unused-value"
    "-Wno-deprecated-declarations"
    "-Wno-narrowing"
    "-Wno-class-memaccess"
    "-Wno-missing-field-initializers"
    "-Wno-ignored-qualifiers"
    "-Wno-sequence-point"
    "-Wno-invalid-offsetof"
    "-Wno-reorder"
    "-Wno-return-type"
    "-Wno-switch"
    "-Wno-parentheses"
    "-Wno-format"
    "-Wno-unused-parameter"
    "-Wno-unused-label"
    "-Wno-type-limits"
    "-Wno-comment"
    "-Wno-catch-value"
    "-Wno-stringop-overflow"
    "-Wno-stringop-truncation"
    "-DBOOST_BIND_GLOBAL_PLACEHOLDERS"
    "-DBOOST_ALLOW_DEPRECATED_HEADERS"
    "-DBOOST_BIND_GLOBAL_PLACEHOLDERS"
    "-D_GLIBCXX_USE_CXX11_ABI=1"
    "-I${opencv}/include/opencv4"
    "-I${boost177}/include"
  ];

  env.PKG_CONFIG_PATH = "${opencv}/lib/pkgconfig:${boost177}/lib/pkgconfig";

  meta = {
    description = "Self-developed Fused deposition modeling slicing software produced by Creality";
    changelog = "https://github.com/CrealityOfficial/CrealityPrint/blob/v${finalAttrs.version}/README.md";
    homepage = "https://github.com/CrealityOfficial/CrealityPrint";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ donteatoreo ];
    platforms = lib.platforms.unix;
    mainProgram = "creality-print";
  };
})
