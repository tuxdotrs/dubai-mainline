# Known issues and open work

## USB gadget dies in stage-2

Once the ADSP starts (`qcom_q6v5_pas`), the gadget stays bound and the role is
`device`, but the UDC reports "not attached" and the host sees nothing.
Re-binding the gadget and toggling the role don't help (the
`usb-gadget-rebind` service doesn't fix it). Same under pmOS. Suspect: the
**fsa4480** Type-C switch (i2c 4-0042) / pmic_glink altmode not routing USB2
D+/D-; dmesg shows `pmic_glink_altmode: failed to acquire mode-switch for
port: 0` as deferred. Workaround: SSH over Wi-Fi; for USB access boot with
`module_blacklist=qcom_q6v5_pas` (no Wi-Fi then). Note ABL replaces the
cmdline, so that needs a debug path (e.g. a stage-1 that writes the blacklist
into modprobe config).

## Mobile data

GSM connection flaps (`InvalidHandle` on deactivate) and floods D-Bus; keep it
off. Next steps: set APN `jionet`, check `qmapmux0.0`/rmnet setup and
ModemManager's QMI over qrtr data path. See userspace.md.

## Firewall

`firewall.service` fails: `xt_pkttype` (and maybe other xt_ matches) not in
pmOS' kernel config. Add `CONFIG_NETFILTER_XT_MATCH_PKTTYPE=m` (and check
`nixos-fw` needs: `xt_conntrack`, `xt_LOG`, `nf_log_syslog`).

## Other

- Plymouth segfaults (harmless).
- Only 144 Hz exposed (120/90/60 modes missing, as on pmOS).
- Voice-call audio not set up (pmOS: q6voiced + VoiceCall UCM verb).
- SIM recovery after suspend under Plasma not verified.
- Nothing marks the slot successful → retry counter runs down over many
  boots; `fastboot --set-active=a` resets it. A safe fix would flip only the
  slot attribute bits (qbootctl-style), never rewrite the GPT.
- Ramdisk headroom below the DTB offset is ~2 MB; adding stage-1 modules or
  firmware can overflow it.
- Mobile NixOS kernel-builder DEPMOD bug (kernels ≥ 7.3) to report upstream.

## Dual boot with LineageOS (analysis, not done)

Possible as one OS per A/B slot (NixOS slot a, Lineage slot b; switch with
`fastboot --set-active` or qbootctl from NixOS). Blocker: both need
`userdata`. Options: put the NixOS rootfs in `super` (8.5 GiB; delete slot a's
logical partitions in fastbootd and create a `nixos` one — tight for the
current ~14 GB system), or shrink userdata (GPT edit — avoid). Lineage OTA must
be disabled (it writes the inactive slot = NixOS).
