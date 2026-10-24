# Mobile NixOS on the Motorola Edge 30 (dubai)

postmarketOS' mainline kernel (its binary package, unpacked) with
[Mobile NixOS](https://github.com/mobile-nixos/mobile-nixos) and Phosh.
Device support is a port of pmOS `device-motorola-dubai`; the pmaports recipes
it follows are in `reference/pmaports/`.

## Layout

    configuration.nix          the system on the phone (user, Phosh, ssh, ...)
    default.nix                entry point: Mobile NixOS + this device + configuration.nix
    devices/motorola-dubai/    device definition (out-of-tree Mobile NixOS device)
      default.nix              boot image, stage-1, USB, SoC
      kernel/                  the pmOS kernel package linux-postmarketos-qcom-sc7280, unpacked
      firmware.nix             FairBlobs/dubai-firmware + linux-firmware subset
      qcom.nix                 rmtfs, tqftpserv, hexagonrpcd, bootmac, sensors, modem
      sound.nix                sc7280 ALSA UCM + wireplumber tweaks
    mobile-nixos/              Mobile NixOS checkout, branch `motorola-dubai`
    flash.sh                   fastboot flashing
    reference/pmaports/        pmOS recipes this is ported from
    stuff-might-need-later/    building the kernel from source (parked, see its README)

`mobile-nixos/` carries small commits on top of upstream (it also pins nixpkgs,
in `npins/`): the `qualcomm-sm7325` SoC, `mobile.system.android.bootimg.extraArgs`
(ABL on dubai needs a header v2 boot image with a DTB section), and stage-1
fixes (console for init, zstd initrd, non-fatal udev trigger). It is not in
this repo; the commits are kept as `mobile-nixos-patches/`. To recreate it:

    git clone https://github.com/mobile-nixos/mobile-nixos
    git -C mobile-nixos checkout -b motorola-dubai 2c132754323fc1915e8d21dcfc0ef68ab084c6fb
    git -C mobile-nixos am ../mobile-nixos-patches/*.patch

After changing it, refresh the patches:
`git -C mobile-nixos format-patch 2c132754..HEAD -o ../mobile-nixos-patches`.

## Build

The system is built for aarch64 natively through binfmt (most of it comes from
cache.nixos.org). The kernel isn't compiled: it is pmOS' build, taken from
mirror.postmarketos.org. The mirror only keeps the latest revision; to update,
bump the revision and hash in devices/motorola-dubai/kernel/default.nix.

    nix-build -A outputs.default

`result/` then has `boot.img` and `system.img` (ext4 rootfs, label NIXOS_SYSTEM).

Panel variant: `motorola-dubai.panel = "tianma";` in configuration.nix if the
bootloader screen shows a Tianma panel (default is CSOT).

## Flash (replaces pmOS)

    ./flash.sh

Flashes an empty dtbo and boot.img to slot b (`SLOT=a ./flash.sh` for the
other), the rootfs to userdata, and switches to that slot. LineageOS on the
other slot is left alone (its userdata is not, it's shared).
vbmeta was already flashed with verification disabled by pmbootstrap.

On first boot the rootfs grows to fill userdata. Login: `user` / `1234`
(also the Phosh PIN); change it with `passwd`.

## Updating

Build on the PC and push over the network (USB, Wi-Fi, ...):

    nixos-rebuild switch --file default.nix --target-host user@<phone-ip> --elevate sudo

Mobile NixOS boots the newest generation from the rootfs, but the kernel and
stage-1 come from boot.img, which nixos-rebuild does not rewrite. After a
change to the kernel or stage-1, re-flash it:

    nix-build -A outputs.android.android-bootimg -o result-boot
    fastboot flash boot_b result-boot

## How boot works here

ABL ignores the boot.img cmdline and passes its own, including `init=/init` and
no `root=`. The Mobile NixOS stage-1 skips that `init=`, finds the rootfs by its
NIXOS_SYSTEM label and boots `/nix/var/nix/profiles/system` (or, on first boot,
the system in `/nix-path-registration`). Slot b is marked successful by
Mobile NixOS boot-control, so ABL doesn't fall back to slot a after 7 boots.

## Debugging

If the phone doesn't come up, stage-1 exposes USB networking (RNDIS) and the
recovery GUI; logs are kept in /run/log during stage-1 and pstore
(`/sys/fs/pstore`) survives a crash into Lineage or pmOS.

## Not done yet

- voice call audio (pmOS uses q6voiced + the VoiceCall UCM verb)
- 120/90/60 Hz display modes (only 144 Hz is exposed, as on pmOS)
- regenerating boot.img on `nixos-rebuild` (kexec stage-0 is not enabled)
