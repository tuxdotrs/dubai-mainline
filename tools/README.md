# tools

| File | What |
|---|---|
| `debug-boot-img.sh` | Builds `build/boot-debug.img`: the current stage-1 with a busybox init that keeps a telnet shell on USB (172.16.42.1:23) while NixOS' stage-1 runs as a child. For `fastboot boot` only. Usage and workflow: [docs/troubleshooting.md](../docs/troubleshooting.md#debug-boot-image-the-tool-that-found-the-7-3-boot-loop). Needs `./build.sh kernel system` first; busybox, mkbootimg, zstd, cpio and python3 come from the pinned nixpkgs. |
| `gpt-XT2203-1_RETIN_U1RDS34.80-40-5-6.bin` | Stock partition table (`gpt.bin`) from Motorola firmware XT2203-1_DUBAI_RETIN_14_U1RDS34.80-40-5-6. MD5 `bc10ae52e292286468a18d4bfac05c10` (as listed in that firmware's `flashfile.xml`), SHA-256 `a1bac446034307efccf507efc19549975b1cf74cebd2bcf9110e67ee152799fe`. Restores a corrupted GPT: `fastboot flash partition gpt-…bin`. Only for this model/region/bootloader. See [docs/deploy.md](../docs/deploy.md#recovering-a-corrupted-gpt). |
