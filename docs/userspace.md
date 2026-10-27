# Userspace

Everything here is ported from pmOS (`device-motorola-dubai`, `soc-qcom`,
`soc-qcom-modem`, `soc-qcom-sc7280`) unless noted.

## Firmware (`userspace/devices/motorola-dubai/firmware.nix`)

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

## Qualcomm services (`userspace/devices/motorola-dubai/qcom.nix`)

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

### Sensors (accelerometer, light, proximity)

They sit on the ADSP's sensor core (SSC), reached through
`hexagonrpcd-adsp-sensorspd` and libssc; nixpkgs' iio-sensor-proxy is built
with `ssc-support`. Two fixes in `qcom.nix`:

- iio-sensor-proxy's own udev rule only tags the ADSP with `ssc-light
  ssc-compass`; accelerometer and proximity are opt-in per device. We add
  `ssc-accel ssc-proximity` (`IIO_SENSOR_PROXY_TYPE` on `fastrpc-adsp*`).
  Without it the proxy logs "No sensors or missing kernel drivers" and exits,
  and there is no auto-rotate.
- The SSC rebuilds its registry at every boot (hexagonrpcd can't open
  `/mnt/vendor/persist/sensors/registry`) and doesn't answer for ~40 s, so the
  first iio-sensor-proxy run finds nothing and exits cleanly. The unit now
  starts after the sensors PD and restarts on success (every 10 s, at most 10
  times in 5 min); the second run finds all three sensors, ~1 min after boot.

Check with `busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy
net.hadess.SensorProxy HasAccelerometer`. Claiming a sensor needs an active
session (polkit), so over SSH use `sudo monitor-sensor`.

### SIM: provisioning session (important quirk)

Symptom: ModemManager reports **sim-missing** although the SIM is present;
`qmicli -d qrtr://0 --uim-get-card-status` shows
`Primary GW: session doesn't exist`. On Android the RIL activates the
provisioning session; on Linux nothing does.

Fix: `sim-provisioning.service` (long-running watcher) polls the card status
every 5 s; when the session doesn't exist it finds the first present card's
USIM AID, runs the command below, then `systemctl try-restart ModemManager`
(which otherwise stays in `failed`):

```sh
qmicli -d qrtr://0 --uim-change-provisioning-session="slot=$slot,activate=yes,session-type=primary-gw-provisioning,aid=$aid"
```

After resume ModemManager drops the modem ("couldn't check support for device
'qcom-soc'"); `modem-resume.service` (wanted by `suspend.target`) restarts
ModemManager. (Not verified with the current desktop.)

Why a watcher and not a oneshot: every modem restart drops the session, and
the modem can restart on its own. Seen at boot: no tqftpserv requests, kernel
`failed to announce new service` (QRTR name service), then
`qcom_q6v5_pas … fatal error received: dog_hal_common.c:177:DOG detects
stalled initialization` at ~76 s and again at ~142 s. The old oneshot gave
up after ~60 s and the SIM stayed "missing". The stall itself was a QRTR
race, fixed by a kernel patch (kernel.md, Patches). Tested: deactivating the
session by hand → the watcher re-activates it within 5 s and ModemManager
re-registers.

Result: registered on JIO, LTE/5G NR.

### Mobile data — not working, keep it off

Plasma's first-run wizard (previous desktop) created a GSM connection "Internet". Activating it
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

## Desktop: Denial (`userspace/configuration.nix`, `userspace/denial/`)

[Denial](https://github.com/denialwm/denial) (Rust/Smithay compositor, Flutter
shell), pinned in `userspace/denial/source.nix`. Its own Nix package is
x86_64-only (pinned x86-64 Flutter engine and Dart SDK), so:

- **ARM64 build**: `./build.sh denial` in the meta repo runs Denial's
  CROSS_BUILDING.md in a Debian trixie container (`tools/denial/Dockerfile`,
  `tools/denial/cross-build.sh`; needs docker on the build host). It builds the
  Flutter engine (gclient checkout of Denial's flutter/skia forks, gn/ninja;
  ~50 min on the first run, then cached in `~/.cache/denial-docker`), assembles
  the shell plus the Settings and Polkit Flutter apps for linux-arm64, and
  cross-compiles the compositor, portal, polkit agent and `denial-app` runner
  against the container's arm64 multiarch libraries. Output:
  `build/denial/denial-linux-arm64-<rev>.tar.gz` (~48 MB), local only: a fresh
  clone must run it before `./build.sh system` (the configuration asserts the
  file exists).
- **Package** (`userspace/denial/default.nix`): that payload plus the
  packaging files of the same revision, laid out like Denial's
  `nix/package.nix` (session script, systemd user units, portals, `.desktop`
  files; Settings and the Polkit dialog share the shell's engine). The
  dlopened libraries (libglvnd, PAM, PulseAudio, ddcutil) go through
  `autoPatchelfHook`'s `runtimeDependencies`: upstream's postFixup
  `--add-rpath` is lost when autoPatchelf rewrites the runpath, and deniald
  then panics with `libEGL.so.1: cannot open shared object file`. Not built:
  the plugin manager.
- **Module**: Denial's own `nix/module.nix`, imported from the pinned source
  without its flake overlay (that one would build the x86 package): session,
  portals, Xwayland, polkit agent, rtkit.
- **Session**: greetd `initial_session` logs `user` into `denial-session` on
  VT1 (once per boot; tuigreet after the session exits).
  `/etc/denial/session.conf` pins `DENIAL_DRM_DEVICE`/`DENIAL_RENDER_DEVICE`
  to the msm card (`card1`/`renderD128`; `card0` is simpledrm and disappears
  at the handoff) and sets `DENIAL_SHELL_PROFILE=mobile`: touch gestures, the
  home pill and a built-in on-screen keyboard. Upstream calls the mobile shell
  a development shell.
- **Per-user state**, not in the NixOS config:
  - `~/.config/denial/settings.json`, applied live. The shell's
    `power.powerButtonAction` defaults to `powerOff`; set it to `dpms` so a
    short press only turns the screen off.
  - `~/.local/state/denial/outputs.conf`: `scale=DSI-1,<s>`,
    `transform=DSI-1,<90|180|270>`, `mode=DSI-1,1080,2400,<millihz>`. Read only
    when the compositor starts (no live reload, no output-management
    protocol). Default scale 1.0 is tiny on this ~400 ppi panel.
- **Tools**: `denialctl outputs` / `status` (with
  `XDG_RUNTIME_DIR=/run/user/1000`), `denial-session --check` (resolved DRM
  devices, bundle, profile). Running the session with logs: troubleshooting.md.
- GPU: freedreno (Adreno 642L, "Adreno 7c+ Gen 3"), GLES 3.2 for Impeller.
  Panel modes 144/120/90/60/48 Hz; Denial picks 144. Lag: known-issues.md.
- Haptics via `programs.feedbackd`; kitty as terminal.
- Previous desktops: Plasma Mobile (up to system-43), Phosh (up to system-5).

## Waydroid

`virtualisation.waydroid.enable`; needs `CONFIG_ANDROID_BINDERFS=y`
(kernel.md). Once: `sudo waydroid init`, which downloads the LineageOS 20
vanilla arm64 system and vendor images (~2.4 GB) into `/var/lib/waydroid`.
Under `systemd-run` it needs `--setenv=PATH=...`, else it fails with
`No such file or directory: 'mkdir'`. `waydroid-container` starts at boot;
the session runs inside Denial (`wayland-1`). Vendor type MAINLINE, GPU
through Mesa.

## Plymouth

ABL passes `console=null`, so `/proc/consoles` is empty and stock plymouthd
segfaults (`strcmp` on NULL in `kernel_console_is_ttynull`).
`userspace/devices/motorola-dubai/plymouth-empty-proc-consoles.patch` fixes that; the
splash then runs until the display manager starts. `systemctl --failed` should
be empty on a healthy boot.
