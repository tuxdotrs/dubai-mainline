# Mobile NixOS on the Motorola Edge 30 (dubai)

The [sc7280-mainline](https://github.com/sc7280-mainline/linux) kernel with
[Mobile NixOS](https://github.com/mobile-nixos/mobile-nixos) and Plasma Mobile.
Device support is a port of pmOS `device-motorola-dubai`.

**Before changing anything, read [docs/](docs/README.md)**: device quirks, the
boot chain, kernel build pitfalls, deployment, rollback and troubleshooting.

## Layout

A meta repo with one submodule per part:

    build.sh       entry point: ./build.sh [kernel|system|boot|images|bootloader]
    scripts/       per-part build scripts called by build.sh
    flash.sh       fastboot flashing of a full image
    tools/         debug boot image builder, stock gpt.bin (GPT recovery)
    docs/          device notes, quirks, troubleshooting
    bootloader/    tuxdotrs/dubai-mainline-bootloader: U-Boot chainloaded by ABL (WIP)
    kernel/        tuxdotrs/dubai-mainline-kernel: sc7280-mainline + config + patches
    userspace/     tuxdotrs/dubai-mainline-userspace: NixOS config, device module, Mobile NixOS

Each submodule has its own README. The kernel tracks sc7280-mainline tags
directly and U-Boot tracks upstream releases; Mobile NixOS is upstream too.
None of them is forked: changes live in each repo's `patches/` (for Mobile
NixOS: the `qualcomm-sm7325` SoC, `mobile.system.android.bootimg.extraArgs`
and stage-1 fixes).

## Getting the sources

    git clone --recursive --shallow-submodules git@github.com:tuxdotrs/dubai-mainline.git
    # or, in an existing clone:
    git submodule update --init --recursive --depth 1

## Build

    ./build.sh [kernel|system|boot|images|bootloader] [-- nix-build args]

Results are symlinks in `build/`, logs in `build/logs/`. `images` gives
`build/images/boot.img` and `system.img` (ext4 rootfs, label NIXOS_SYSTEM).
The kernel is cross-compiled from x86_64; the rest is built for aarch64 through
binfmt, mostly from cache.nixos.org.

Options for `userspace/configuration.nix`:

- `motorola-dubai.kernel = "prebuilt";` uses pmOS' kernel package
  (`kernel/prebuilt`) instead of building `kernel/`.
- `motorola-dubai.panel = "tianma";` if the bootloader screen shows a Tianma
  panel (default is CSOT).

### Bumping the kernel

    git -C kernel/linux fetch --depth 1 origin tag v7.3.1-sc7280
    git -C kernel/linux checkout v7.3.1-sc7280
    # set `version` in kernel/default.nix, build, commit in kernel/, then here:
    git add kernel

## Flash

    SLOT=a ./flash.sh build/images

Flashes an empty dtbo and boot.img to the slot, the rootfs to userdata, and
activates the slot. Bootloader fastboot refuses `flash userdata`; use
fastbootd. vbmeta was already flashed with verification disabled.

On first boot the rootfs grows to fill userdata. Login: `user` / `1234`;
change it with `passwd`.

## Updating a running phone

See [docs/deploy.md](docs/deploy.md): `nix copy` the system, set the profile,
and write boot.img to `boot_a` when the kernel or stage-1 changed.

## How boot works here

ABL loads boot.img (kernel + Mobile NixOS stage-1) from `boot_a`; the stage-1
finds the rootfs by its NIXOS_SYSTEM label and boots
`/nix/var/nix/profiles/system`. Details and quirks:
[docs/boot-chain.md](docs/boot-chain.md). The U-Boot port in `bootloader/`
aims to load the kernel from the rootfs instead.

## Not done yet

See [docs/known-issues.md](docs/known-issues.md).
