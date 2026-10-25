# Device

## Identity

| | |
|---|---|
| Name | Motorola Edge 30, codename **dubai** |
| Model | XT2203-1, RETIN (India retail) |
| SoC | Qualcomm SM7325 (Snapdragon 778G+), mainline name **sc7280** family ("yupik") |
| RAM / storage | 8 GB / 128 GB Samsung UFS (KMAG9001PM-B814) |
| Display | 1080×2400 OLED, 144 Hz, Novatek NT37701 DSC command-mode panel; two vendors: **CSOT** and **Tianma** |
| Touch | Goodix Berlin over SPI (`goodix_berlin_spi`) |
| GPU | Adreno 642L ("Adreno 7c+ Gen 3" in Mesa), freedreno, firmware a660_* |
| Wi-Fi/BT | WCN6750 (ath11k_ahb), firmware runs on the WPSS remoteproc |
| Audio | WCD937x codec, 2× AW88261 amps, q6afe/APR on the ADSP |
| Fastboot product | `dubai` |
| Bootloader | ABL `MBM-3.0-dubai_g-…-U1RDS34.80-40-5-6`, unlocked |
| Stock build | XT2203-1_DUBAI_RETIN_14_U1RDS34.80-40-5-6 (Android 14) |

The panel vendor shows in the bootloader screen and in ABL's cmdline
(`msm_drm.dsi_display0=qcom,mdss_dsi_mot_csot_nt37701_…`). The device tree must
match: `sm7325-motorola-dubai-csot.dtb` vs `-tianma.dtb`
(`motorola-dubai.panel` option). This unit is **CSOT**.

## Partitions

A/B device, 77 partition labels across 6 UFS LUNs (sda…sdf). The ones that
matter:

| Label | Size | Used for |
|---|---|---|
| `boot_a` / `boot_b` | 96 MiB | Android boot.img v2 (kernel + DTB + stage-1 initrd) |
| `dtbo_a` / `dtbo_b` | 24 MiB | **Must be zeroed** for mainline (ABL can't apply the stock overlay) |
| `vendor_boot_a/_b` | 96 MiB | Stock; untouched |
| `vbmeta_a/_b` | small | Flashed with verification disabled (done once by pmbootstrap) |
| `super` | 8.5 GiB | Android dynamic partitions (unused by NixOS) |
| `userdata` | ~108 GiB | **NixOS rootfs** (ext4, label `NIXOS_SYSTEM`) |
| `modemst1/2`, `fsg_a/_b`, `fsc`, `persist`, `prodpersist` | small | Modem NV data, IMEI, calibration — **back up, never overwrite** |

`/dev/disk/by-partlabel/<name>` works from Linux. Slot partitions of slot a
live on sdd, slot b on sdf; userdata/super/modem on sde.

## Current layout of this unit

- Slot **a**: NixOS boot.img, `dtbo_a` zeroed. Active slot.
- Slot **b**: an old debug boot image (`boot-debug3`); not bootable as a system.
- `userdata`: NixOS rootfs. LineageOS (previously on the other slot) is gone.

## Bootloader (ABL) facts

- Unlocked; `androidboot.verifiedbootstate=orange`.
- **Replaces the boot.img cmdline with its own.** It passes `console=null`,
  `init=/init`, `androidboot.*`, `rootwait ro`, no `root=`. Whatever is in the
  boot.img cmdline is effectively ignored for a normal boot.
- Marks a normal boot with `androidboot.force_normal_boot=1` (not
  `skip_initramfs`).
- Requires boot.img **header v2** with a DTB section, and also uses a DTB
  appended to the kernel.
- A/B retry counter: 7 tries. Nothing marks the NixOS slot successful (see
  boot-chain), so the counter runs down; `fastboot --set-active=a` resets it to
  7.
- Bootloader fastboot refuses `flash userdata` (permission denied); use
  **fastbootd** (`fastboot reboot fastboot`) for that.
- `systemctl reboot --reboot-argument=bootloader` does **not** reach fastboot;
  use **Power + Volume Down**.
- `fastboot boot <img>` works: boots an image from RAM without flashing. On a
  crash the phone falls back to the active slot. Ideal for testing.
