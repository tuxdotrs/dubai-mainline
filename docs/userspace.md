# Userspace

Everything here is ported from pmOS (`device-motorola-dubai`, `soc-qcom`,
`soc-qcom-modem`, `soc-qcom-sc7280`) unless noted.

## Firmware (`devices/motorola-dubai/firmware.nix`)

From https://github.com/FairBlobs/dubai-firmware (pmOS
`firmware-motorola-dubai`), installed to `lib/firmware/qcom/sm7325/motorola/dubai/`:
`modem.mbn`, `adsp.mbn`, `cdsp.mbn`, `wpss.mbn` (+ `*.jsn`, `modem_pr/`),
`a660_zap.mbn`, `yupik_ipa_fws.mbn`, `vpu20_1v.mbn`, `aw88261_acf.bin`.
Plus `board-2.bin` for `ath11k/WCN6750/hw1.0/` (replaces the generic one), the
linux-firmware subset pmOS pulls in (ath11k, qca, `qcom/a660_sqe.fw`,
`a660_gmu.bin`), and the hexagonrpcd root (`share/qcom/sm7325/Motorola/dubai`,
sensors + socinfo). Unfree; allowed via `allowUnfreePredicate`.

Remoteprocs and their firmware (`/sys/class/remoteproc/*/{name,firmware,state}`):
`modem`, `adsp`, `wpss` (Wi-Fi), `cdsp` — all should be `running`.

## Qualcomm services (`devices/motorola-dubai/qcom.nix`)

The Mobile NixOS overlay pins 2020-era qrtr/rmtfs/tqftpserv for SDM845, so the
current ones are built from nixpkgs expressions directly (`fromNixpkgs`).
qrtr-ns and pd-mapper are in-kernel on this kernel — not needed.

| Service | Why |
|---|---|
| `rmtfs -r -P -s` | modem remote filesystem (modemst1/2, fsg); needs `/dev/qcom_rmtfs_mem1` |
| `tqftpserv` 1.3 (+ `-populate-readwrite`) | TFTP for the modem; 1.3 reads `/sys/module/firmware_class/parameters/path` and `.zst`; populate copies `rfs/msm/mpss` from persist (pmOS preset) |
| `hexagonrpcd-adsp-rootpd`, `-sensorspd` | sensors through libssc / iio-sensor-proxy (`-R` hexagonfs root) |
| `bootmac` | sets Wi-Fi/BT MACs from ABL's `wifimacaddr`/`androidboot.btmacaddr` |
| `sim-provisioning` (ours) | see below |
| `modem-resume` (ours) | see below |

Also: `fastrpc` user/group + udev rule, accelerometer mount matrix
(`ACCEL_MOUNT_MATRIX=-1,0,0;0,-1,0;0,0,-1`), UPower thresholds and
`GST_PLUGIN_FEATURE_RANK` from pmOS.

### SIM: provisioning session (important quirk)

Symptom: ModemManager reports **sim-missing** although the SIM is present;
`qmicli -d qrtr://0 --uim-get-card-status` shows
`Primary GW: session doesn't exist`. On Android the RIL activates the
provisioning session; on Linux nothing does.

Fix: `sim-provisioning.service` (oneshot, before ModemManager) parses the card
status, finds the first present card's USIM AID and runs:

```sh
qmicli -d qrtr://0 --uim-change-provisioning-session="slot=$slot,activate=yes,session-type=primary-gw-provisioning,aid=$aid"
```

After resume ModemManager drops the modem ("couldn't check support for device
'qcom-soc'"); `modem-resume.service` (wanted by `suspend.target`) re-runs
provisioning and restarts ModemManager. (Not yet verified under Plasma.)

Result: registered on JIO, LTE/5G NR.

### Mobile data — not working, keep it off

The Plasma first-run wizard creates a GSM connection "Internet". Activating it
loops: ModemManager "connects", NM's deactivation fails with
`QMI protocol error (9): 'InvalidHandle'`, repeat — hundreds of
ActiveConnection objects per minute. Side effect: plasmashell's
QDBusConnection thread pins ~70% CPU polling dead objects → **the UI and touch
feel unresponsive**. Recovery: `nmcli c down Internet`, then
`systemctl --user restart plasma-plasmashell`. Needs the APN (`jionet` for
Jio) and a look at the qrtr/rmnet (`qmapmux0.0`) data path.

## Wi-Fi

ath11k_ahb on WPSS, works once the `wpss` remoteproc runs. Interface `wld0`.
Credentials are stored system-wide by NetworkManager. The DHCP address changes
every boot (no reservation).

## Audio (`sound.nix`, `alsa-ucm-conf.nix`)

UCM profiles from https://github.com/sc7280-mainline/alsa-ucm-conf (pmOS
`alsa-ucm-conf-qcom-sc7280`), used through `mobile.quirks.audio.alsa-ucm-meld`
(ALSA_CONFIG_UCM2) instead of overriding `pkgs.alsa-ucm-conf`, which would
rebuild everything linking alsa-lib. WirePlumber rule `51-qcom` (S16LE, 48 kHz,
period 4096×6, headroom 512). Audio and camera work. The wcd937x
"Impedance detect ramp error" / q6afe "Unknown cmd" messages at boot are
harmless. Voice-call audio is not done (pmOS uses q6voiced).

## Desktop: Plasma Mobile (`configuration.nix`)

nixpkgs has no Plasma Mobile option: enable Plasma 6, SDDM (wayland),
`sessionPackages = [ kdePackages.plasma-mobile ]`,
`defaultSession = "plasma-mobile"`, autologin (SDDM's greeter isn't touch
friendly; the Plasma Mobile lock screen uses the user password as PIN).

Quirks:

- **On-screen keyboard (Maliit) never appears** unless KWin's input method is
  set: `/etc/xdg/kwinrc` `[Wayland] InputMethod=/run/current-system/sw/share/applications/com.github.maliit.keyboard.desktop`, `VirtualKeyboardEnabled=true`.
- **ibus breaks the OSK** (GTK_IM_MODULE=ibus bypasses the Wayland input
  method): `i18n.inputMethod.enable = lib.mkForce false`. This was found under
  Phosh and still applies.
- GPU: freedreno, "Adreno 7c+ Gen 3", OpenGL 4.6 (Mesa 26.x), KWin
  compositing works; display runs at 144 Hz only.
- Haptics via `programs.feedbackd`.
- Previous desktop was Phosh (generations ≤ system-5).

## Known-harmless failed units

- `plymouth-start.service`: plymouthd segfaults; boot works without it.
