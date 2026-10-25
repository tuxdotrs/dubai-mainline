# Building and deploying

## Build host

Anything x86_64 with Nix and aarch64 binfmt (for the non-kernel parts; most
comes from cache.nixos.org). The kernel is cross-compiled, so binfmt isn't
used for it. The owner builds on a 16-core box (`arcturus`) over SSH and copies
results back:

```sh
git clone --recursive --shallow-submodules <repo>     # or: git submodule update --init --depth 1
./build.sh kernel system boot -- --cores 16 -j 6      # results in build/, logs in build/logs/
```

`build.sh` targets map to:

| target | nix attribute |
|---|---|
| kernel | `(import ./default.nix {}).config.mobile.boot.stage-1.kernel.package` |
| system | `-A config.system.build.toplevel` |
| boot | `-A outputs.android.android-bootimg` |
| images | `-A outputs.default` (boot.img + system.img) |

Kernel builds take ~10–15 min on 16 cores; a fresh clone of the repo produces
bit-identical derivations (verified).

## Reaching the phone

- **SSH over Wi-Fi** as `user` (password/PIN from `configuration.nix`;
  `sudo` uses the same password). The address changes every boot — find it by
  host key:

  ```sh
  FP=SHA256:9zaPZgcARqUHHbIC9pj4i91Q0JsEh8D5EOCGXE3vOGs   # this unit's ed25519 host key
  for i in $(seq 2 254); do (fp=$(ssh-keyscan -T 3 -t ed25519 192.168.1.$i 2>/dev/null \
    | ssh-keygen -lf - 2>/dev/null | awk '{print $2}'); [ "$fp" = "$FP" ] && echo 192.168.1.$i) & done; wait
  ```
  Scan the **whole /24**; it has landed above .100 before.
- **USB networking works only before the ADSP starts** (stage-1, or a boot
  with `module_blacklist=qcom_q6v5_pas`): phone 172.16.42.1, PC 172.16.42.2.
  See [known-issues.md](known-issues.md#usb-gadget-dies-in-stage-2).

## Updating a running phone (normal path)

The kernel and stage-1 come from boot.img; everything else (incl. modules) from
the system profile. Change them together.

From the PC (`$IP` = phone; `sudo` reads the password from stdin with `-S`):

```sh
SYS=$(readlink -f build/system); BOOT=$(readlink -f build/boot)

# 1. back up the current boot partition to the PC
ssh user@$IP 'sudo dd if=/dev/disk/by-partlabel/boot_a bs=4M status=none' > boot_a.backup.img

# 2. copy the system and boot image
nix copy --no-check-sigs --to ssh://user@$IP $SYS
scp $BOOT user@$IP:/tmp/boot-new.img

# 3. activate the system for next boot ("do not know how to make this
#    configuration bootable" is expected: boot.img is the boot loader)
ssh user@$IP "sudo nix-env -p /nix/var/nix/profiles/system --set $SYS &&
              sudo $SYS/bin/switch-to-configuration boot"

# 4. only if the kernel or stage-1 changed: write boot_a and verify
ssh user@$IP 'sudo dd if=/tmp/boot-new.img of=/dev/disk/by-partlabel/boot_a bs=4M conv=fsync &&
              sudo head -c $(stat -c %s /tmp/boot-new.img) /dev/disk/by-partlabel/boot_a | sha256sum'
sha256sum $BOOT            # must match

# 5. reboot (don't touch the power button for ~20 s)
ssh user@$IP 'sudo systemctl reboot'
```

For userspace-only changes steps 1, 4 can be skipped.

Backups kept on the owner's PC (`~/Projects/dubai/backup/`):
`nixos-7.2.9/boot_a.img` (pmOS prebuilt kernel), `nixos-7.3.0-mnbuilder/boot_a.img`
(7.3.0 via Mobile NixOS builder), stock boot/dtbo/vbmeta/vendor_boot for both
slots, `modem/` (modemst1/2, fsg_a/b, fsc, persist, prodpersist + SHA256SUMS),
`stock-U1RDS34.80-40-5-6/gpt.bin`.

## Testing a boot image without flashing

Power + Volume Down → fastboot, then `fastboot boot build/boot`. It boots once
from RAM; a crash falls back to the active slot. Note it still boots the
*profile's* system, so modules only match if the profile has the same kernel.

## Full flash (fresh install / reinstall)

`./build.sh images`, then in fastboot: `SLOT=a ./flash.sh build/images`. It
writes a zeroed dtbo, boot.img, the rootfs to `userdata`, sets the slot active
and reboots. Bootloader fastboot refuses `flash userdata` → do it from
**fastbootd** (`fastboot reboot fastboot`; if needed boot a stock/Lineage boot
image first so fastbootd exists). First boot grows the rootfs to fill
userdata.

## Rollback

Boot loop or bad kernel:

```sh
# Power + Volume Down → fastboot
fastboot flash boot_a <backup boot_a.img>
fastboot --set-active=a          # also resets the retry counter to 7
fastboot reboot
```

Then fix the profile to the generation matching that kernel
(`ls -l /nix/var/nix/profiles/`; `nix-env -p /nix/var/nix/profiles/system --set <path>`;
`switch-to-configuration boot`; reboot) — otherwise stage-2 boots with the
wrong kernel's modules: no Wi-Fi, no remoteprocs, but USB networking at
172.16.42.1 works (ADSP never starts), which is how to get in.

## Recovering a corrupted GPT

Symptoms: ABL boots only to fastboot, `fastboot getvar slot-count` = 1, no
partitions. Restore the stock partition table:

1. Use `tools/gpt-XT2203-1_RETIN_U1RDS34.80-40-5-6.bin` (the stock `gpt.bin`,
   MD5 bc10ae52e292286468a18d4bfac05c10 as listed in Motorola's
   `flashfile.xml`). It comes from firmware
   `XT2203-1_DUBAI_RETIN_14_U1RDS34.80-40-5-6` (mirrors-obs-1.lolinet.com),
   which matches this unit's bootloader; for another region/build, take
   `gpt.bin` from the matching firmware.
2. `fastboot flash partition tools/gpt-XT2203-1_RETIN_U1RDS34.80-40-5-6.bin`,
   reboot to bootloader, re-check `getvar all`. Data partitions are untouched
   by this; boot/dtbo may need re-flashing.
