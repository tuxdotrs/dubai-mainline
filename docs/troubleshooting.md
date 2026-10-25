# Troubleshooting

## First questions

1. **Did the kernel reach stage-2?** On a working boot:
   `journalctl --list-boots` and `journalctl -b <n> | grep -m1 "Linux version"`.
   A failed boot that never shows up in the journal died in the kernel or
   stage-1.
2. **Does boot.img match the system profile?** `uname -r` vs
   `ls /run/current-system/kernel-modules/lib/modules/` and
   `readlink /nix/var/nix/profiles/system`.
3. **What does USB show?** `lsusb`:
   - `22b8:2e80 Motorola … Fastboot dubai` — bootloader fastboot.
   - `18d1:d001 Google … Nexus 4` — Mobile NixOS stage-1 gadget (RNDIS,
     172.16.42.1).
   - nothing — booting, ADSP up (gadget dead), or off.

## Symptom → cause

| Symptom | Likely cause | Where |
|---|---|---|
| Boot loop, never in journal, gadget appears ~45 s then reset | stage-1 exception (exit 99), e.g. initrd without modules | read `/.error.json` with the debug image below; kernel.md #4 |
| Boot loop immediately after kernel start, EBADF | no `/dev/console` for PID 1 | boot-chain.md (fixed in fork) |
| Stops at a "generation" menu every boot | `boot_as_recovery = true` | boot-chain.md |
| ABL shows no partitions / only fastboot, slot-count 1 | GPT rewritten (boot-control) | deploy.md GPT recovery |
| Boots, but no Wi-Fi, no remoteprocs, USB 172.16.42.1 works | kernel in boot.img ≠ modules of the profile | deploy.md rollback |
| No remoteprocs / Wi-Fi with the prebuilt kernel | empty `modules.dep` from the apk | kernel-prebuilt runs `depmod` |
| Phone powers off ~15–30 s into boot, journal "Power key pressed short" | someone pressed power before Plasma started | harmless |
| UI/touch laggy, plasmashell QDBusConnection thread ~70% CPU | mobile-data connection flapping | userspace.md, `nmcli c down Internet` + restart plasmashell |
| SIM "missing" | no UIM provisioning session | `sim-provisioning.service` |
| OSK never shows | KWin InputMethod unset or ibus active | userspace.md |
| Phone not found on LAN | new DHCP address, possibly > .100 | scan whole /24 by host key (deploy.md) |
| Touch "not responsive" | check `grep goodix /proc/interrupts` grows when touching; if yes the input path is fine and the shell is busy | top -H on plasmashell |

## Logs

- Stage-2: `journalctl -b`, `journalctl -b -1`, `dmesg` (needs sudo).
- Stage-1: no persistent log. Mobile NixOS keeps logs under `/run/log`
  during stage-1 and writes `/.error.json` on failure — both lost on reboot.
- pstore: empty (`CONFIG_PSTORE_RAM` off). Enabling `PSTORE_RAM`,
  `PSTORE_CONSOLE` would give crash logs across warm reboots (DT already has
  `ramoops@ae000000`).
- Background services: `systemctl --failed`; a `plymouth-start` failure is
  known and harmless. `firewall` works since the netfilter options were added
  to kernel/config (it used to fail on `xt_pkttype`).

## Debug boot image (the tool that found the 7.3 boot loop)

Idea: keep a shell alive while the real stage-1 runs, so its failure can be
inspected. Build an initrd from the system's stage-1 initrd with:

- NixOS' `/init` renamed to `/init.nixos`;
- a static aarch64 busybox in `/debug/` and the gadget modules (`libcomposite
  u_ether usb_f_ncm u_serial usb_f_acm`, decompressed from the kernel's
  modules output) in `/debug/modules/`;
- a new `/init` (busybox sh) that mounts proc/sys/dev/devpts/configfs,
  insmods the modules, forces `usb_role` to device, creates a configfs gadget
  with NCM + ACM, sets 172.16.42.1, starts `telnetd -l /debug/sh -p 23`, waits
  for `/debug/go` (or 90 s), then runs
  `env -i HOME=/ TERM=linux /init.nixos <&- >&- 2>&-` **as a child** (PID 1
  stays busybox, so a stage-1 failure doesn't reboot) and sleeps forever.

Repack with `cpio -o -H newc | zstd -19`, `cat Image.gz dtb > kernel`, and
`mkbootimg --header_version 2 … --dtb … --dtb_offset 0x1f00000` with the same
offsets as boot-chain.md; check the ramdisk end. Boot it with
`fastboot boot` only.

All of that is **`tools/debug-boot-img.sh`**: run `./build.sh kernel system`,
then `tools/debug-boot-img.sh` → `build/boot-debug.img`, then
`fastboot boot build/boot-debug.img`.

Using it:

```sh
# the NCM link gets a new interface name on the PC; give it an address
nmcli device modify <enp…i2> ipv4.method manual ipv4.addresses 172.16.42.2/24
nc 172.16.42.1 23                 # busybox shell (zsh has no /dev/tcp; use nc)
touch /debug/go                   # start NixOS stage-1
dmesg | grep "=="                 # debug-init markers, "/init.nixos exited: N"
cat /.error.json                  # Mobile NixOS' exception + backtrace
```

Pitfall (handled by the script): the debug interface must not be called
`usb0` (it renames it to `dbg0`), or stage-1's DHCPD task fires before PATH is
set and fails with a misleading "Command not found (127)". The debug gadget
also holds the UDC, so stage-1's own USB gadget can't bind; if stage-1 stops
at its gadget task in this setup, treat that as a debug artifact (not
verified either way) and check whether the error is about binding the UDC.

## Inspecting an initrd / boot.img offline

```sh
zstd -dc $(readlink -f build/system/initrd) | cpio -t --quiet | grep '\.ko'   # stage-1 modules
nix log $(nix-store -q --deriver <...-shrunk>)   # makeModulesClosure: which modules weren't found
```

boot.img header (v2): `struct.unpack('<8x9I', hdr[:44])` → kernel size, kernel
addr, ramdisk size, ramdisk addr, second size/addr, tags addr, page size,
header version. Kernel is gzip + appended DTB.

## Remote debugging helpers

- CPU hogs per thread: `top -H -bn1 -p <pid>`.
- D-Bus storms: `busctl monitor --system` for 5 s, count senders/members.
- Kernel interrupts for a device: `grep <name> /proc/interrupts` twice.
- Modem: `mmcli -m any`, `qmicli -d qrtr://0 --uim-get-card-status`.
