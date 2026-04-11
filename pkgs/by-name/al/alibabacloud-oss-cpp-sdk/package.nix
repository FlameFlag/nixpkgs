{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  curl,
  openssl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "alibabacloud-oss-cpp-sdk";
  version = "1.9.2";

  src = fetchFromGitHub {
    owner = "aliyun";
    repo = "aliyun-oss-cpp-sdk";
    tag = finalAttrs.version;
    hash = "sha256-XOtOtU4H4oIgNEUBbC06VGpLEuzmPaeRRpCRIUuBL6g=";
  };

  nativeBuildInputs = [ cmake ];

  buildInputs = [
    curl
    openssl
  ];

  env.NIX_CFLAGS_COMPILE = "-Wno-error";

  cmakeFlags = [
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
    (lib.cmakeBool "BUILD_SAMPLE" false)
    (lib.cmakeBool "BUILD_TESTS" false)
    (lib.cmakeFeature "CMAKE_POLICY_VERSION_MINIMUM" "3.5")
  ];

  meta = {
    description = "Alibaba Cloud OSS SDK for C++";
    homepage = "https://github.com/aliyun/aliyun-oss-cpp-sdk";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
  };
})
