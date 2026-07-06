{
  lib,
  buildPythonPackage,
  fetchPypi,
  pydantic,
  setuptools,
}:

buildPythonPackage (finalAttrs: {
  pname = "hyprpy";
  version = "0.1.10";
  pyproject = true;

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchPypi {
    pname = finalAttrs.pname;
    version = finalAttrs.version;
    hash = "sha256-OX8iOglHMFAwq0LT1cE4nhpP9BxgWFcgc3potqSNIAg=";
  };

  build-system = [ setuptools ];

  dependencies = [ pydantic ];

  pythonImportsCheck = [ "hyprpy" ];

  meta = {
    description = "Python bindings for the Hyprland compositor";
    homepage = "https://github.com/ulinja/hyprpy";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ _4evy ];
  };
})
