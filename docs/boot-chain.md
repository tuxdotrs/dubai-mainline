# Boot chain

    ABL (bootloader)
     └─ boot_a: boot.img v2 ─ kernel (Image.gz + appended DTB), DTB section, initrd
         └─ Mobile NixOS stage-1 (initrd, mruby init)
             ├─ loads stage-1 modules (panel, touch, USB gadget)
             ├─ USB networking 172.16.42.1 (RNDIS)
             ├─ finds rootfs by label NIXOS_SYSTEM on userdata
             └─ switch_root → /nix/var/nix/profiles/system/init
                 └─ NixOS stage-2 (systemd) → Plasma Mobile

## boot.img

Built by Mobile NixOS' android system type
(`userspace/mobile-nixos/modules/system-types/android/`) with these settings from
`userspace/devices/motorola-dubai/default.nix` (values from pmOS `deviceinfo_flash_*`):

| | |
|---|---|
| header version | 2 (`--header_version 2`, via the fork's `bootimg.extraArgs`) |
| pagesize | 4096 |
| base / kernel / ramdisk / tags offset | 0x0 / 0x8000 / 0x01000000 / 0x100 |
| DTB section | `--dtb …/sm7325-motorola-dubai-<panel>.dtb --dtb_offset 0x01f00000` |
| appended DTB | yes (`appendDTB`), kernel = Image.gz + dtb |
| os_patch_level | 2026-06-26 |
| initrd compression | **zstd -19** (fork adds the option) |

**Ramdisk size limit**: the ramdisk loads at 0x01000000 and the DTB at
0x01f00000, so the ramdisk must stay under **15 MiB**. With gzip the initrd was
~15.8 MB and overlapped → zstd. Current sizes: ~12.9 MB with the
linuxManualConfig kernel (stripped modules), ~14.9 MB with unstripped modules.
Check every new image:

```python
import struct
b = open("boot.img", "rb").read(4096)
ks, ka, rs, ra = struct.unpack_from("<4I", b, 8)
print("ramdisk ends", hex(ra + rs), "OK" if ra + rs < 0x1f00000 else "OVERLAP")
```

`dtbo` must be zeroed (`flash.sh` writes 24 MiB of zeros): ABL can't apply the
stock overlay to the mainline DTB.

## Stage-1 (Mobile NixOS initrd)

Device settings that matter, and why:

- `mobile.system.android.boot_as_recovery = false` — ABL signals a normal boot
  with `androidboot.force_normal_boot=1`; in "boot as recovery" mode every boot
  stopped at the stage-1 generation menu.
- `has_recovery_partition = false`, `system_partition_destination = "userdata"`.
- `mobile.boot.boot-control.enable = false` and cmdline
  `systemd.mask=boot-control.service` — **boot-control corrupted the GPT**
  (see README rules). The mask in the cmdline covers older generations, but
  remember ABL replaces the cmdline, so the real protection is the disabled
  module.
- Stage-1 modules (pmOS `modules-initfs`): `panel_novatek_nt37701`,
  `spi_geni_qcom`, `goodix_berlin_core`, `goodix_berlin_spi`; additional:
  `libcomposite`, `usb_f_fs`, `usb_f_rndis`, `usb_f_mass_storage`.
- Stage-1 firmware: `qcom/a660_*` and `a660_zap.mbn` (msm is built-in and may
  request GPU firmware before stage-2).
- `mobile.boot.stage-1.networking.enable = true` plus the device task
  `usb-role.rb`, which forces `/sys/class/usb_role/*/role` to `device` —
  without the ADSP running, pmic-glink can't report the Type-C role and no
  gadget would appear.

### Fixes carried in the mobile-nixos fork (branch `motorola-dubai`)

| Symptom | Cause | Fix (in fork) |
|---|---|---|
| Kernel panic loop right after "Run /init", EBADF | ABL passes `console=null`; the initrd has no device nodes, so PID 1 starts with stdin/out/err closed and the first write fails | init wrapper `mknod /.console c 5 1` and `/.null c 1 3` and redirects stdio (`modules/initrd.nix`) |
| Stage-1 aborts at udev | `udevadm trigger` fails because qcom-battmgr power supplies return EAGAIN until the ADSP runs | trigger failure made non-fatal (`boot/init/tasks/udev.rb`) |
| Ramdisk overlaps DTB | gzip initrd too big | `mobile.boot.stage-1.compression = "zstd"` |
| ABL rejects the image | needs header v2 + DTB section | `mobile.system.android.bootimg.extraArgs`, `qualcomm-sm7325` SoC |

### How stage-1 picks the system

It ignores ABL's `init=/init`, finds `NIXOS_SYSTEM`, and boots
`/nix/var/nix/profiles/system` (on first boot: the system in
`/nix-path-registration`). So **the kernel comes from boot.img but the modules
come from the profile's system**. If boot.img and the profile disagree on the
kernel version, stage-2 has no modules (no Wi-Fi, no remoteprocs). Always
change both together.

### Stage-1 failure handling

On an uncaught error, Mobile NixOS writes `/.error.json` (code, message,
backtrace) and exits with status 99 (`INIT_EXCEPTION`); PID 1 exiting panics
the kernel and ABL reboots. That is what a "boot loop" looks like here.
[troubleshooting.md](troubleshooting.md) shows how to read that file.

Ordering quirk worth knowing: the stage-1 DHCPD task depends only on a
`usb0` interface existing, not on the Environment task that sets `PATH`. If
`usb0` exists too early (e.g. created by a debug init), `ifconfig` runs with no
PATH and fails with "Command not found (127)".

## Boot log on the display

The boot is verbose on purpose: `userspace/configuration.nix` turns off
Mobile NixOS' silentBoot and splash and the stage-1 GUI, and sets
`boot.consoleLogLevel = 7`; the kernel console is `tty1`. `CONFIG_DRM_SIMPLEDRM`
puts the console on the framebuffer U-Boot leaves behind (DT
`/chosen/framebuffer`, 0xe1000000) from ~0.3 s; at ~1.6 s msm takes the
display over (aperture handoff), the console is on msmdrmfb from ~1.9 s until
sddm takes VT1. Without simpledrm the screen stayed black until Plasma even
though fbcon bound to msm at 1.6 s. The handoff prints 4 harmless
`dsi0_phy_pll_out_byteclk already disabled` warnings (simpledrm releasing
clocks msm already reset). The ABL boot.img on boot_a still has the old
quiet cmdline until it's reflashed.

## Stage-2

Normal NixOS (systemd). Boot to Plasma takes ~15 s after stage-2 starts.

- The **power key** is handled by logind until Plasma starts; a short press in
  the first ~15 s powers the phone off cleanly ("Power key pressed short. /
  Powering off…" in the journal). Not a bug — just don't touch it while
  booting.
- **Clock**: the RTC isn't trusted; the clock is wrong until NTP syncs over
  Wi-Fi, so journal timestamps of early boots overlap.
- `/sys/fs/pstore` stays empty: `CONFIG_PSTORE_RAM` is off in pmOS' config
  even though the DT reserves `ramoops@ae000000`.

## U-Boot path (installed on boot_b, the active slot)

`bootloader/` builds mainline U-Boot as a boot.img that ABL loads like a
kernel (gzip'd `u-boot-nodtb.bin` + the dubai DTB, same header as above):
ABL → U-Boot (boot_b) → generation menu → kernel + Mobile NixOS initrd from
the rootfs. Since 2026-10-26 slot b is active: dtbo_b zeroed, vbmeta_b with
verification disabled, boot_b = `build/bootloader/u-boot.img`. boot_a still
holds the Linux boot.img (ABL → kernel directly); `fastboot --set-active=a`
switches back. Kernel and stage-1 updates now arrive with
`switch-to-configuration boot` alone (no boot_a write) when booting via U-Boot.

- **UFS needs U-Boot past v2026.10.** ABL leaves the UFS 3.1 `vcc` rail (L7B)
  off; without ufs-qcom's regulator support (upstream main, 2026-10-19) UFS
  fails with "link startup failed / Device not present". Don't switch L7B on
  by hand from v2026.10's shell: its RPMh regulator code reset the phone.
- **Menu:** `u-boot.nix` also writes `/boot/extlinux/u-boot-menu.env`, one
  `bootmenu` item per generation (volume keys + power) plus U-Boot's tools;
  `dubai_boot` imports it, extlinux.conf is the fallback. Volume up needs the
  PM7325 GPIO patch in `bootloader/patches/` and VIN1 (set in preboot).
- **extlinux.conf** is written by `userspace/devices/motorola-dubai/u-boot.nix`
  on every `switch-to-configuration boot/switch`: NixOS' generic-extlinux
  builder into `/boot` on the rootfs (10 generations), each APPEND ending in
  `${abl_bootargs}`. The entry's `init=<generation>/init` picks the generation
  (Mobile NixOS' stage-1 honours `init=` except ABL's `init=/init`).
- **ABL's command line** (androidboot.*, wifimacaddr, btmacaddr) is in the
  DTB's `/chosen/bootargs`; `dubai_boot` in `bootloader/dubai.env` copies it to
  `$abl_bootargs`. U-Boot passes its own control DTB to Linux (no FDT line),
  which prints harmless `reserving fdt memory region failed … -17`.
- **Debugging:** U-Boot's menu (shown after a failed boot, or hold power)
  has "Enable serial console gadget": a U-Boot shell on `/dev/ttyACM0`.
  `fastboot oem console` jams U-Boot's fastboot; prefer the serial console.
- A U-Boot `fastboot boot` of another image chainloads it with U-Boot's
  fixed-up DTB: no ABL bootargs, `u-boot,version` in `/chosen`. Test from
  Motorola's fastboot (Power + Volume Down) instead.
