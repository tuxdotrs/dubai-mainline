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

## Other

- Only 144 Hz exposed (120/90/60 modes missing, as on pmOS).
- Voice-call audio not set up (pmOS: q6voiced + VoiceCall UCM verb).
- SIM recovery after suspend under Plasma not verified.
- Ramdisk headroom below the DTB offset is ~2 MB; adding stage-1 modules or
  firmware can overflow it.
- Mobile NixOS kernel-builder DEPMOD bug (kernels ≥ 7.3) to report upstream.
- `kernel/patches/qrtr-ns-wait-for-hello.patch` to send upstream (netdev).

## U-Boot

- Generation menu: U-Boot `bootmenu` built from /boot/extlinux/u-boot-menu.env
  (volume keys + power, 5 s timeout to the default). bootstd's `bootflow menu`
  can't list generations: one bootflow per partition for extlinux and BLS.
- Volume up (PM7325 GPIO 6) needs VIN1; the pinctrl state's
  `power-source = <1>` doesn't end up in the register (0x8d41 reads 0 after
  boot, unexplained), so dubai.env's preboot writes it with `pmic write`.
  With VIN0 the key reads as held and the menu ignores it.
- `fastboot boot` tests still count down the active slot's retries (only a
  NixOS boot that reaches multi-user.target marks the slot successful). At 0
  ABL marks the slot unbootable and silently switches slots (slot a hit this
  on 2026-10-26). `fastboot --set-active=<slot>` resets the counter.

- 4 `dsi0_phy_pll_out_byteclk already disabled/unprepared` warnings when msm
  takes the display over from simpledrm (~1.6 s). A boot clk trace shows
  simpledrm enabling disp_cc_mdss_byte0/pclk0 at ~0.3 s with no event on the
  DSI PHY PLL clocks, and no clk_set_parent before the release. When the PHY
  registers its clocks (~0.6 s), orphan adoption prepares the still
  unconfigured PLL ("DSI PLL(0) lock failed"); `__clk_set_parent_before`
  ignores that error and the counts end up unbalanced. Making simpledrm wait
  for the PHY (DT) fixes the warnings but loses the early boot log. Not the
  cause of the dark console (that was the panel reset timing, boot-chain.md).

## Dual boot with LineageOS (analysis, not done)

Possible as one OS per A/B slot (NixOS slot a, Lineage slot b; switch with
`fastboot --set-active` or qbootctl from NixOS). Blocker: both need
`userdata`. Options: put the NixOS rootfs in `super` (8.5 GiB; delete slot a's
logical partitions in fastbootd and create a `nixos` one — tight for the
current ~14 GB system), or shrink userdata (GPT edit — avoid). Lineage OTA must
be disabled (it writes the inactive slot = NixOS).
