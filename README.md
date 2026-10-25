# Mobile NixOS on the Motorola Edge 30 (dubai)

The [sc7280-mainline](https://github.com/sc7280-mainline/linux) kernel with
[Mobile NixOS](https://github.com/mobile-nixos/mobile-nixos) and Plasma Mobile.
Device support is a port of pmOS `device-motorola-dubai`.

## Layout

    build.sh                   build entry point (see below)
    default.nix                Mobile NixOS + this device + configuration.nix
    configuration.nix          the system on the phone (user, Plasma Mobile, ssh, ...)
    kernel/
      linux/                   submodule: sc7280-mainline/linux, tag v7.3.0-sc7280
      config                   kernel config: pmOS' linux-postmarketos-qcom-sc7280 config
      default.nix              kernel build (LLVM=1, cross-compiled)
    mobile-nixos/              submodule: tuxdotrs/mobile-nixos, branch motorola-dubai
                               (also pins nixpkgs, in npins/)
    devices/motorola-dubai/    device definition (out-of-tree Mobile NixOS device)
      default.nix              boot image, stage-1, USB, kernel choice
      kernel-prebuilt/         fallback kernel: pmOS' binary package, unpacked
      firmware.nix             FairBlobs/dubai-firmware + linux-firmware subset
      qcom.nix                 rmtfs, tqftpserv, hexagonrpcd, bootmac, sensors, modem, SIM
      sound.nix                sc7280 ALSA UCM + wireplumber tweaks
    flash.sh                   fastboot flashing of a full image
    stuff-might-need-later/    pmOS' exact clang 23 toolchain (parked)

The mobile-nixos fork carries what dubai needs on top of upstream: the
`qualcomm-sm7325` SoC, `mobile.system.android.bootimg.extraArgs` (ABL wants a
header v2 boot image with a DTB section), and stage-1 fixes (console for init,
zstd initrd, non-fatal udev trigger).

## Getting the sources

    git clone --recursive --shallow-submodules <this repo>
    # or, in an existing clone:
    git submodule update --init --depth 1

## Build

    ./build.sh [kernel|system|boot|images]      # default: images

Results are symlinks in `build/`, logs in `build/logs/`. `images` gives
`build/images/boot.img` and `system.img` (ext4 rootfs, label NIXOS_SYSTEM).
Each target is a plain nix-build too:

    nix-build -E '(import ./default.nix {}).config.mobile.boot.stage-1.kernel.package'
    nix-build -A config.system.build.toplevel
    nix-build -A outputs.android.android-bootimg
    nix-build -A outputs.default

The kernel is cross-compiled from x86_64 (`motorola-dubai.kernelBuildSystem`);
the rest is built for aarch64 natively through binfmt, mostly from
cache.nixos.org.

Options for configuration.nix:

- `motorola-dubai.kernel = "prebuilt";` uses pmOS' kernel package instead of
  building kernel/.
- `motorola-dubai.panel = "tianma";` if the bootloader screen shows a Tianma
  panel (default is CSOT).

### Bumping the kernel

    git -C kernel/linux fetch --depth 1 origin tag v7.3.1-sc7280
    git -C kernel/linux checkout v7.3.1-sc7280
    # set `version` in kernel/default.nix, build, then
    git add kernel/linux kernel/default.nix

`make oldconfig` takes defaults for options kernel/config doesn't have; the
build log shows them. To refresh kernel/config, copy the newer one from
pmaports (`device/community/linux-postmarketos-qcom-sc7280`).

## Flash

    SLOT=a ./flash.sh build/images

Flashes an empty dtbo and boot.img to the slot, the rootfs to userdata, and
activates the slot. Bootloader fastboot refuses `flash userdata`; use
fastbootd. vbmeta was already flashed with verification disabled.

On first boot the rootfs grows to fill userdata. Login: `user` / `1234`;
change it with `passwd`.

## Updating a running phone

USB networking doesn't work once the ADSP is up, so this goes over Wi-Fi:

    ./build.sh system boot
    nix copy --to ssh://user@<phone-ip> ./build/system
    ssh user@<phone-ip>
      sudo nix-env -p /nix/var/nix/profiles/system --set <system path>
      sudo <system path>/bin/switch-to-configuration boot

Mobile NixOS boots the newest generation from the rootfs, but the kernel and
stage-1 come from boot.img. After a kernel or stage-1 change also write it:

    dd if=boot.img of=/dev/disk/by-partlabel/boot_a     # on the phone, or
    fastboot flash boot_a build/boot

## How boot works here

ABL ignores the boot.img cmdline and passes its own, including `init=/init` and
no `root=`. The Mobile NixOS stage-1 skips that `init=`, finds the rootfs by its
NIXOS_SYSTEM label and boots `/nix/var/nix/profiles/system`.

Mobile NixOS boot-control is disabled: it marks the slot successful with
sgdisk, which rewrote the GPT so that ABL found no partitions. Nothing marks the
slot successful now, so after a few boots `fastboot --set-active=a` resets
the retry counter.

## Not done yet

- USB networking in stage-2 (gadget "not attached" once the ADSP runs, also on pmOS)
- mobile data (the connection flaps; keep it off)
- voice call audio (pmOS uses q6voiced + the VoiceCall UCM verb)
- 120/90/60 Hz display modes (only 144 Hz is exposed, as on pmOS)
