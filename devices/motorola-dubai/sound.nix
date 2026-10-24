{ config, lib, pkgs, ... }:

{
  # Alsa UCM profiles (pmOS alsa-ucm-conf-qcom-sc7280)
  mobile.quirks.audio.alsa-ucm-meld = true;
  environment.systemPackages = [
    (pkgs.callPackage ./alsa-ucm-conf.nix { })
  ];

  # pmOS soc-qcom 51-qcom.conf
  services.pipewire.wireplumber.extraConfig."51-qcom" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          { "node.name" = "~alsa_input.*"; }
          { "node.name" = "~alsa_output.*"; }
        ];
        actions.update-props = {
          "audio.format" = "S16LE";
          "audio.rate" = 48000;
          "api.alsa.period-size" = 4096;
          "api.alsa.period-num" = 6;
          "api.alsa.headroom" = 512;
        };
      }
    ];
  };
}
