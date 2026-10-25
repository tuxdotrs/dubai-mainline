# Motorola Edge 30 (dubai) — NixOS port notes

Everything learned while bringing up mainline Linux + NixOS on this phone:
what the hardware and bootloader do, why the code is the way it is, and how to
debug it when it breaks. Written to be read by a person or an LLM picking the
project up cold.

## Read in this order

| File | What's in it |
|---|---|
| [device.md](device.md) | Hardware, partitions, bootloader facts, identifiers |
| [boot-chain.md](boot-chain.md) | ABL → boot.img → Mobile NixOS stage-1 → stage-2, and every boot quirk |
| [kernel.md](kernel.md) | Kernel source, config, toolchain, build pitfalls and how to verify a build |
| [userspace.md](userspace.md) | Firmware, Qualcomm services, modem/SIM, Wi-Fi, audio, Plasma Mobile, OSK |
| [deploy.md](deploy.md) | Building, updating a running phone, full flash, backups, rollback |
| [troubleshooting.md](troubleshooting.md) | Debugging methods (debug boot image, logs) and a symptom → cause table |
| [known-issues.md](known-issues.md) | What doesn't work yet, and ideas for each |

## Rules that must not be broken

These each cost hours; one nearly bricked the phone.

1. **Never let anything rewrite the GPT.** Mobile NixOS `boot-control` uses
   `sgdisk` to mark the slot successful; it rewrote the whole GPT and the
   bootloader then saw no partitions. It is disabled
   (`mobile.boot.boot-control.enable = false`) and masked on the cmdline. If
   slot marking is ever needed, flip attribute bits only (as pmOS' `qbootctl`
   does). Recovery needs the stock `gpt.bin` — see [deploy.md](deploy.md#recovering-a-corrupted-gpt).
2. **Back up `boot_a` before writing a new one**, and keep the matching system
   generation: a generation only carries its own kernel's modules.
3. **Back up the modem partitions before any risky flash** (modemst1/2, fsg,
   fsc, persist, prodpersist). They hold IMEI/calibration; they're already
   backed up in `~/Projects/dubai/backup/modem/` on the owner's laptop.
4. **Check the ramdisk end against the DTB offset** (`0x1f00000`) for every new
   boot.img. Overlap = silent boot failure.
5. **Never trust "it built" for the kernel**: verify `modules.dep` exists, the
   initrd contains its `.ko` files, and diff the final `.config`
   ([kernel.md](kernel.md#verifying-a-kernel-build)).

## Repository map

    build.sh                   ./build.sh [kernel|system|boot|images] → build/
    default.nix                Mobile NixOS + device + configuration.nix
    configuration.nix          the phone's system (Plasma Mobile, user, ssh…)
    kernel/linux/              submodule: sc7280-mainline/linux (tag v7.3.0-sc7280)
    kernel/config              pmOS kernel config (+ HW_RANDOM_QCOM)
    kernel/default.nix         nixpkgs linuxManualConfig, clang/lld, cross
    mobile-nixos/              submodule: tuxdotrs/mobile-nixos, branch motorola-dubai
    devices/motorola-dubai/    device module, firmware, qcom services, sound
    flash.sh                   full fastboot flash
    tools/                     debug boot image builder, stock gpt.bin (GPT recovery)
    stuff-might-need-later/    parked clang-23 toolchain (pmOS' exact compiler)

Upstream references used throughout: postmarketOS pmaports
(`device/community/device-motorola-dubai`, `linux-postmarketos-qcom-sc7280`,
`soc-qcom*`), https://github.com/sc7280-mainline/linux,
https://github.com/FairBlobs/dubai-firmware.
