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

## Denial: lag (open, investigated 2026-10-27)

Denial feels laggy, nowhere near 144 Hz smooth. Measured with Denial's render
audit (`DENIAL_RENDER_AUDIT=1`, docs/RENDER_AUDIT.md upstream), a DRM
`drm_vblank_event` trace and a raw touch event dump:

- **Not touch input**: the Goodix panel reports steadily at ~370 Hz.
- **Not GPU throughput**: the GPU is at most 28 % busy while interacting.
- Animations Denial drives itself run at a clean 144 Hz (6.9 ms vblank
  intervals); finger-driven updates arrive every 3–10 vblanks.
- With `schedutil`, frames after a pause are 10–20× slower (build 5–9 ms,
  raster 20–35 ms, up to 58 ms, spikes 60–180 ms) than while dragging
  continuously (build ~0.4 ms, raster ~1.5–2 ms, 100–133 fps). Raising the
  GPU's runtime-PM autosuspend from 66 ms to 1 s didn't help. Pinning all
  CPU clusters to `performance` did (raster 1–7 ms, felt better): the CPU
  frequency ramp-up is too slow for bursty UI work.
- Still left at `performance`: heavier frames take 8–10 ms, over the 6.94 ms
  budget at 144 Hz. On this command-mode DSI panel a missed slot costs 3–4
  vblanks (20–28 ms gaps, ~36–50 fps).

Next: try 90 Hz (`mode=DSI-1,1080,2400,90000` in outputs.conf, 11.1 ms budget;
was being tried when this paused), a CPU frequency floor or uclamp for the
session instead of `performance`, Denial's appearance settings (glass/blur)
to cut raster cost, GPU devfreq tuning. Test sessions with the audit:
troubleshooting.md (Logs).

## Denial: other

- The output config (scale, rotation, mode) is read only at compositor
  start; changes need a session restart.
- The Welcome window has a fixed 900×620 size and overflows the portrait
  screen.
- If iio-sensor-proxy restarts while Denial runs, Denial keeps its old claim
  and auto-rotate stops until Denial restarts (it only reconnects when a
  claim fails).
- `switch-to-configuration switch` while Denial runs outside greetd (a manual
  `systemd-run` session) starts tuigreet on the same VT; `systemctl mask
  --runtime greetd` doesn't prevent it (`/etc` overrides `/run`). No issue when
  greetd started Denial.
- The plugin manager isn't built for ARM64.

## Sensors start slowly

The SSC has no persisted registry (`/mnt/vendor/persist/sensors/registry`
missing) and rebuilds it each boot, so sensors appear ~1 min after boot
(userspace.md, Sensors). Making the `persist` partition available there,
read-only first, should fix it and keep the factory calibration.

## Other

- Panel modes 144/120/90/60/48 Hz are exposed; Denial uses 144 by default.
- Voice-call audio not set up (pmOS: q6voiced + VoiceCall UCM verb).
- SIM recovery after suspend not verified with the current desktop.
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
