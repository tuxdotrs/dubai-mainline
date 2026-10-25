# Motorola Edge 30 (dubai), SM7325, mainline kernel.
# Ported from pmOS device-motorola-dubai (see ../../reference/pmaports).
{ config, lib, pkgs, ... }:

let
  cfg = config.motorola-dubai;

  # The kernel is cross-compiled when the host can't build aarch64 natively,
  # since building it under binfmt emulation takes hours.
  kernelPkgs =
    if cfg.kernelBuildSystem == null || cfg.kernelBuildSystem == pkgs.stdenv.buildPlatform.system
    then pkgs
    else import pkgs.path {
      localSystem = cfg.kernelBuildSystem;
      crossSystem = pkgs.stdenv.hostPlatform.system;
      inherit (pkgs) overlays;
    };
  kernel =
    if cfg.kernel == "source"
    then kernelPkgs.callPackage ../../kernel { }
    else pkgs.callPackage ./kernel-prebuilt { };

  dtb = "dtbs/qcom/sm7325-motorola-dubai-${cfg.panel}.dtb";
in
{
  imports = [
    ./qcom.nix
    ./sound.nix
  ];

  options.motorola-dubai = {
    kernel = lib.mkOption {
      type = lib.types.enum [ "source" "prebuilt" ];
      default = "source";
      description = ''
        "source" builds ../../kernel (sc7280-mainline submodule);
        "prebuilt" uses pmOS's binary package from ./kernel-prebuilt.
      '';
    };
    kernelBuildSystem = lib.mkOption {
      type = with lib.types; nullOr str;
      default = "x86_64-linux";
      description = ''
        System the kernel is (cross-)compiled on. null builds it like
        everything else.
      '';
    };
    panel = lib.mkOption {
      type = lib.types.enum [ "csot" "tianma" ];
      default = "csot";
      description = ''
        Display panel variant. In fastboot mode the bootloader shows it as
        the "Panel" string (also: `fastboot getvar all`).
      '';
    };
  };

  config = {
    mobile.device.name = "motorola-dubai";
    mobile.device.identity = {
      name = "Edge 30";
      manufacturer = "Motorola";
    };
    mobile.device.supportLevel = "unsupported";

    mobile.hardware = {
      soc = "qualcomm-sm7325";
      ram = 1024 * 8;
      screen = {
        width = 1080; height = 2400;
      };
    };

    mobile.device.firmware = pkgs.callPackage ./firmware.nix { };

    mobile.boot.stage-1 = {
      # pmOS config has RD_GZIP and RD_ZSTD, not RD_XZ. gzip makes the initrd
      # ~15.8 MB, which loaded at 0x1000000 runs over the dtb at 0x1f00000.
      compression = "zstd";
      kernel = {
        package = kernel;
        modular = true;
        # pmOS modules-initfs: panel and touch, for the stage-1 GUI
        modules = [
          "panel_novatek_nt37701"
          "spi_geni_qcom"
          "goodix_berlin_core"
          "goodix_berlin_spi"
        ];
        additionalModules = [
          "libcomposite"
          "usb_f_fs"
          "usb_f_rndis"
          "usb_f_mass_storage"
        ];
      };
      # msm is built in and may ask for the GPU firmware before stage-2
      firmware = [
        (pkgs.runCommand "initrd-firmware" { } ''
          fw=${config.mobile.device.firmware}/lib/firmware
          mkdir -p $out/lib/firmware/qcom/sm7325/motorola/dubai
          cp $fw/qcom/a660_* $out/lib/firmware/qcom/
          cp $fw/qcom/sm7325/motorola/dubai/a660_zap.mbn $out/lib/firmware/qcom/sm7325/motorola/dubai/
        '')
      ];
    };

    # boot-control marks the slot successful with sgdisk, which rewrites the
    # whole GPT; after it ran, ABL could not read any partition (slot-count 1).
    # pmOS uses qbootctl, which only flips the attribute bits.
    mobile.boot.boot-control.enable = false;

    mobile.system.type = "android";
    mobile.system.android = {
      device_name = "dubai";
      ab_partitions = true;
      # A/B, but ABL marks a normal boot with androidboot.force_normal_boot=1,
      # not skip_initramfs; as "boot as recovery" every boot would stop at the
      # stage-1 generation menu. There is no recovery partition either.
      boot_as_recovery = false;
      has_recovery_partition = false;
      # pmOS flashes its rootfs to userdata as well
      system_partition_destination = "userdata";
      # pmOS deviceinfo_flash_*; ABL wants header v2 with the dtb also
      # appended to the kernel, and replaces the cmdline with its own.
      bootimg.flash = {
        offset_base = "0x00000000";
        offset_kernel = "0x00008000";
        offset_ramdisk = "0x01000000";
        offset_second = "0x00000000";
        offset_tags = "0x00000100";
        pagesize = "4096";
      };
      bootimg.extraArgs = [
        "--header_version" "2"
        "--dtb" "${kernel}/${dtb}"
        "--dtb_offset" "0x01f00000"
        "--os_patch_level" "2026-06-26"
      ];
      appendDTB = [ dtb ];
    };

    # pmOS kernel-cmdline.conf, in case ABL ever passes ours through
    # The mask also covers systems on the rootfs built before boot-control was
    # disabled (see below); ABL keeps the boot.img cmdline.
    boot.kernelParams = [ "earlycon" "systemd.mask=boot-control.service" ];

    # ABL passes console=null, so /proc/consoles is empty and plymouthd
    # segfaults (strcmp on NULL in kernel_console_is_ttynull).
    boot.plymouth.package = pkgs.plymouth.overrideAttrs (o: {
      patches = (o.patches or [ ]) ++ [ ./plymouth-empty-proc-consoles.patch ];
    });

    # USB networking from stage-1 (172.16.42.1, RNDIS); the gadget stays bound
    # in stage-2, so sshd is reachable over USB even when nothing else works.
    mobile.boot.stage-1.networking.enable = true;
    mobile.boot.stage-1.tasks = [ ./usb-role.rb ];

    # Once the ADSP runs, the Type-C stack switches the controller's role and
    # its UDC goes away and comes back, leaving stage-1's gadget unbound.
    # Re-bind it whenever a UDC appears.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="udc", TAG+="systemd", ENV{SYSTEMD_WANTS}+="usb-gadget-rebind.service"
    '';
    systemd.services.usb-gadget-rebind = {
      description = "Re-bind the stage-1 USB gadget";
      wantedBy = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        g=/sys/kernel/config/usb_gadget/g1
        [ -d "$g" ] || exit 0
        [ -z "$(cat "$g/UDC")" ] || exit 0
        udc=$(ls /sys/class/udc | head -n1)
        [ -n "$udc" ] && echo "$udc" > "$g/UDC"
      '';
    };

    mobile.usb.mode = "gadgetfs";
    mobile.usb.idVendor = lib.mkDefault "18D1"; # Google
    mobile.usb.idProduct = lib.mkDefault "D001"; # "Nexus 4"
    mobile.usb.gadgetfs.functions = {
      adb = "ffs.adb";
      mass_storage = "mass_storage.0";
      rndis = "rndis.usb0";
    };
  };
}
