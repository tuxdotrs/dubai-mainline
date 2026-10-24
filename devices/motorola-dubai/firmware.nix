# Port of pmOS firmware-motorola-dubai plus the linux-firmware bits pmOS pulls in
# (linux-firmware-ath11k, linux-firmware-qca, firmware-qcom-adreno-a660).
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  linux-firmware,
}:

stdenvNoCC.mkDerivation {
  pname = "firmware-motorola-dubai";
  version = "20250428";

  src = fetchFromGitHub {
    owner = "FairBlobs";
    repo = "dubai-firmware";
    rev = "56c15ff4e81e6464983397bc93be3ae5f7cfcec4";
    hash = "sha256-rrvjwPZ5r1zcuRY3R735TFkgvczsSEL9U2Gr/LQ2nI8=";
  };

  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    fw=$out/lib/firmware
    dubai=$fw/qcom/sm7325/motorola/dubai
    install -Dm644 -t $dubai \
      a660_zap.mbn adsp.mbn adsp*.jsn aw88261_acf.bin cdsp.mbn cdsp*.jsn \
      yupik_ipa_fws.mbn modem.mbn modem*.jsn vpu20_1v.mbn wpss.mbn
    cp -r modem_pr $dubai/

    # WCN6750 calibration, replaces the generic one from linux-firmware
    install -Dm644 board-2.bin -t $fw/ath11k/WCN6750/hw1.0/

    # hexagonrpcd root (served to the ADSP for sensors); acdb/dsp unused, as in pmOS
    hexagonfs=$out/share/qcom/sm7325/Motorola/dubai
    mkdir -p $hexagonfs
    cp -r hexagonfs/sensors hexagonfs/socinfo $hexagonfs/

    # linux-firmware subset
    lf=${linux-firmware}/lib/firmware
    cp -rn $lf/ath11k $lf/qca $fw/
    install -Dm644 -t $fw/qcom $lf/qcom/a660_sqe.fw* $lf/qcom/a660_gmu.bin*

    runHook postInstall
  '';

  meta = {
    description = "Firmware for the Motorola Edge 30 (dubai)";
    homepage = "https://github.com/FairBlobs/dubai-firmware";
    license = lib.licenses.unfreeRedistributableFirmware;
    platforms = [ "aarch64-linux" ];
  };
}
