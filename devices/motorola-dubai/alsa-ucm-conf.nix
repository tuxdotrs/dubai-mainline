# Port of pmOS alsa-ucm-conf-qcom-sc7280: a full alsa-ucm-conf fork with the
# Motorola/dubai profiles. Used through ALSA_CONFIG_UCM2 instead of replacing
# pkgs.alsa-ucm-conf, which would rebuild everything that links alsa-lib.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation {
  pname = "alsa-ucm-conf-qcom-sc7280";
  version = "6";

  src = fetchFromGitHub {
    owner = "sc7280-mainline";
    repo = "alsa-ucm-conf";
    rev = "3dbb936f0cc85a5d3f12bab12a4578d85768061c";
    hash = "sha256-DatEOr7uOS4BweJTRRND6mPC4Au6XxEJBAOubUj4E5Q=";
  };

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/share/alsa
    cp -r ucm2 $out/share/alsa/
  '';

  meta = {
    description = "ALSA UCM configuration for SC7280/SM7325 devices";
    homepage = "https://github.com/sc7280-mainline/alsa-ucm-conf";
    license = lib.licenses.bsd3;
  };
}
