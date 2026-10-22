# polaris-quadlet

[Polaris](https://github.com/papi-ux/polaris) (a Sunshine fork) as a rootless
podman Quadlet on SteamOS. Everything lives under `~`; the read-only root is never
unlocked.

Tested on SteamOS 3.9.3 with an AMD GPU (Strix Halo) and Polaris 1.4.13; an
earlier revision was tested on Intel. NVIDIA is not covered.

## Files

Install into `~/.config/containers/systemd/`:

| File | Purpose |
|---|---|
| `polaris.build` | Builds `localhost/polaris:latest` from the Containerfile. |
| `polaris/Containerfile` | Arch Linux + the official Polaris Arch package + Intel/AMD VAAPI and Vulkan userspace + gamescope (so Gamescope Stream is offered), plus the wrappers below. |
| `polaris/steam-forward.sh` | Installed as the container's `/usr/bin/steam`; forwards to the host's Steam. |
| `polaris/gamescope-session-forward.sh` | Installed as `/usr/bin/polaris-gamescope-session`; runs Polaris's shipped gamescope session script on the host. |
| `polaris/gamescope-ready-diag.sh` | Debug aid appended to the host copy of the session lib; logs which ownership check failed on a readiness timeout. |
| `polaris.container` | Runs Polaris: host network, host PID (Game Mode detection), `/dev/dri`, `/dev/uinput`, the user runtime dir (PipeWire, gamescope sockets, session bus). |
| `polaris-config.volume` | Named volume for Polaris settings, credentials and pairings. |

Also used: named volumes `polaris-cache` (`~/.cache`) and `polaris-labwc`
(`~/.config/labwc-polaris`), created automatically.

## Install

```sh
mkdir -p ~/.config/containers/systemd
cp -r polaris.build polaris.container polaris-config.volume polaris ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start polaris-build polaris
```

It starts via `xdg-desktop-autostart.target` (Desktop Mode) and
`default.target` (at boot, for Game Mode; enable lingering with
`loginctl enable-linger`). Web UI: `https://<host>:47990`.

## Upgrade

Bump `POLARIS_VERSION` and `POLARIS_SHA256` in `polaris/Containerfile`, then:

```sh
systemctl --user restart polaris-build polaris
```

## How it fits together

- **Unit.** Mirrors upstream's `polaris.service`: `After=graphical-session.target`
  only, deliberately without `PartOf=`, so Polaris outlives Game/Desktop Mode
  switches and an active stream is not cut. Upstream's `PassEnvironment=` is
  emulated with `podman --env NAME` (copied from the user manager, skipped when
  unset). `LimitRTPRIO`/`LimitNICE` let capture/encode/audio workers raise
  priority.
- **Steam.** Steam stays on the host. The container's `/usr/bin/steam`
  (`steam-forward.sh`) runs the host's Steam via `systemd-run --user`,
  forwarding the display Polaris picked plus `POLARIS_*`, `SDL_*`,
  `GAMESCOPE_*`, `STEAM_*`, HDR and audio-sink vars, and unsetting whichever of
  `WAYLAND_DISPLAY`/`DISPLAY` the caller lacks (headless gamescope has no
  `WAYLAND_DISPLAY`). It lives in `/usr/bin` because Private Stream runs
  commands with `PATH=/usr/bin:/bin`.
- **Gamescope Stream.** Rootless podman's user namespace cannot read
  `/proc/<pid>/exe` or `environ` of host processes, so Polaris's gamescope
  session script fails its ownership checks in the container.
  `gamescope-session-forward.sh` copies the shipped script and lib into
  `$XDG_RUNTIME_DIR/polaris-host-gamescope/` and runs them unchanged on the host
  via `systemd-run --user --wait`, with `POLARIS_GAMESCOPE_COMPOSITE_CURSOR=0`
  (SteamOS's gamescope lacks `--pipewire-composite-cursor`) and a 90s readiness
  timeout (Steam can take 30-45s to start).
- **X11.** `/tmp/.X11-unix` is deliberately not mounted: labwc's Xwayland must own
  it, and `Network=host` already shares the host's abstract X sockets.

## Stream modes with VAAPI (Intel/AMD)

| Host state | What Polaris streams | Capture |
|---|---|---|
| Game Mode | The Game Mode screen (Polaris overrides any stream mode) | SHM with VAAPI; GPU (DMA-BUF) with PyroWave |
| Desktop Mode, Private Stream | A private headless labwc | SHM: Polaris hard-disables VAAPI DMA-BUF for this route (issues #409/#410) |
| Desktop Mode, Mirror Desktop | KDE via the portal | Needs approval on the host |

`POLARIS_PORTAL_DMABUF=1` would enable VAAPI DMA-BUF for the Game Mode / portal
route only; it is not set here and untested on this hardware.
