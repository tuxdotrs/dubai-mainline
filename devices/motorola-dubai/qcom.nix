# Userspace for the remote processors (modem, ADSP sensors) and misc SoC bits,
# following pmOS soc-qcom, soc-qcom-modem and device-motorola-dubai.
# The Mobile NixOS overlay pins 2020-era qrtr/rmtfs/tqftpserv for SDM845, so
# the current ones are built from the Nixpkgs expressions directly. qrtr-ns and
# pd-mapper are not needed: this kernel has both in-kernel.
{ config, lib, pkgs, ... }:

let
  fromNixpkgs = name: args:
    pkgs.callPackage (pkgs.path + "/pkgs/by-name/${lib.substring 0 2 name}/${name}/package.nix") args;

  qrtr = fromNixpkgs "qrtr" { };
  qmic = fromNixpkgs "qmic" { };
  rmtfs = fromNixpkgs "rmtfs" { inherit qrtr qmic; };

  # 1.3 reads firmware via /sys/module/firmware_class/parameters/path (set by
  # NixOS), decompresses .zst, and ships tqftpserv-populate-readwrite.service.
  tqftpserv = (fromNixpkgs "tqftpserv" { inherit qrtr; }).overrideAttrs {
    version = "1.3";
    src = pkgs.fetchFromGitHub {
      owner = "linux-msm";
      repo = "tqftpserv";
      tag = "v1.3";
      hash = "sha256-p4LRrlylnRrP2HcFEtjBfRwJm7PWcDFOt4xjliSR9Wo=";
    };
    postPatch = "";
  };

  bootmac = pkgs.callPackage ./bootmac.nix { };

  hexagonfs = "${config.mobile.device.firmware}/share/qcom/sm7325/Motorola/dubai";
in
{
  systemd.packages = [ tqftpserv pkgs.hexagonrpc bootmac ];
  services.udev.packages = [ bootmac ];

  systemd.services = {
    rmtfs = {
      description = "Qualcomm remotefs service";
      wantedBy = [ "multi-user.target" ];
      before = [ "ModemManager.service" ];
      unitConfig.ConditionPathExists = "/dev/qcom_rmtfs_mem1";
      serviceConfig = {
        ExecStart = "${rmtfs}/bin/rmtfs -r -P -s";
        Restart = "always";
        RestartSec = 1;
      };
    };

    # Nothing asks the modem to open a provisioning session for the SIM (on
    # Android the RIL does), so ModemManager sees "GW primary session index
    # unknown" and reports sim-missing. Activate the first USIM of the first
    # present card.
    # The session is lost whenever the modem restarts, and the modem can take
    # minutes to come up (its watchdog sometimes resets it: "DOG detects
    # stalled initialization"), so keep watching rather than run once; after
    # activating, restart ModemManager, which stays failed otherwise.
    sim-provisioning = {
      description = "Keep the SIM provisioning session active";
      wantedBy = [ "multi-user.target" ];
      before = [ "ModemManager.service" ];
      after = [ "rmtfs.service" ];
      path = [ pkgs.libqmi pkgs.gawk pkgs.gnugrep pkgs.coreutils ];
      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
      };
      script = ''
        while sleep 5; do
          status=$(qmicli -d qrtr://0 --uim-get-card-status 2>/dev/null) || continue
          echo "$status" | grep -q "Primary GW: *session doesn't exist" || continue
          read -r slot aid < <(echo "$status" | awk '
            /^Slot \[/ { s = $2; gsub(/[^0-9]/, "", s) }
            /Card state: .present./ { present[s] = 1 }
            /Application type: .*usim/ { usim = 1 }
            usim && /Application ID:/ { getline; gsub(/[ \t]/, ""); if (present[s]) { print s, $0; exit } usim = 0 }') || continue
          qmicli -d qrtr://0 --uim-change-provisioning-session="slot=$slot,activate=yes,session-type=primary-gw-provisioning,aid=$aid" || continue
          systemctl try-restart ModemManager.service || true
        done
      '';
    };

    # After resume ModemManager re-probes the modem and drops it ("couldn't
    # check support for device 'qcom-soc'"); start it over.
    modem-resume = {
      description = "Restart ModemManager after resume";
      wantedBy = [ "suspend.target" ];
      after = [ "suspend.target" ];
      serviceConfig.Type = "oneshot";
      script = "systemctl restart ModemManager.service";
    };

    tqftpserv.wantedBy = [ "multi-user.target" ];
    # Enabled by pmOS 80-device-motorola-dubai.preset; copies rfs/msm/mpss from persist
    tqftpserv-populate-readwrite = {
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.util-linux pkgs.coreutils ];
    };

    # Sensors through libssc / iio-sensor-proxy
    hexagonrpcd-adsp-rootpd = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = [ "" "${pkgs.hexagonrpc}/bin/hexagonrpcd -f /dev/fastrpc-adsp -d adsp -R ${hexagonfs}" ];
    };
    hexagonrpcd-adsp-sensorspd = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = [ "" "${pkgs.hexagonrpc}/bin/hexagonrpcd -f /dev/fastrpc-adsp -d adsp -s -R ${hexagonfs}" ];
    };
  };

  users.users.fastrpc = {
    isSystemUser = true;
    group = "fastrpc";
  };
  users.groups.fastrpc = { };

  services.udev.extraRules = ''
    KERNEL=="fastrpc-*", MODE="0660", GROUP="fastrpc"
    # pmOS 81-libssc-motorola-dubai.rules: accelerometer mount matrix
    SUBSYSTEM=="misc", KERNEL=="fastrpc-*", ENV{ACCEL_MOUNT_MATRIX}+="-1, 0, 0; 0, -1, 0; 0, 0, -1"
  '';

  hardware.sensor.iio.enable = lib.mkDefault true;
  networking.modemmanager.enable = lib.mkDefault true;

  # pmOS soc-qcom: UPower.conf and gstreamer.conf
  services.upower = {
    percentageLow = 10;
    percentageCritical = 5;
    percentageAction = 3;
    criticalPowerAction = "PowerOff";
  };
  environment.sessionVariables.GST_PLUGIN_FEATURE_RANK =
    "v4l2vp8dec:SECONDARY,v4l2vp8enc:NONE,v4l2vp9dec:SECONDARY,v4l2h264dec:SECONDARY,v4l2h264enc:NONE,v4l2h265dec:SECONDARY,v4l2h265enc:NONE,v4l2mpeg2dec:SECONDARY";
}
