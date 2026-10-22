# polaris-quadlet

[Polaris](https://github.com/papi-ux/polaris) (a Sunshine fork) as a rootless
podman Quadlet on SteamOS. Everything lives under `~`; the read-only root is never
unlocked.

Tested on SteamOS 3.9 with an Intel GPU and Polaris 1.4.13. AMD userspace is
included but untested; NVIDIA is not covered.

## Files

Install into `~/.config/containers/systemd/`:

| File | Purpose |
|---|---|
| `polaris.build` | Builds `localhost/polaris:latest` from the Containerfile. |
| `polaris/Containerfile` | Arch Linux + the official Polaris Arch package + Intel/AMD VAAPI and Vulkan userspace, plus a `steam` wrapper that forwards to the host's Steam. |
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

It starts with `graphical-session.target` (both Game Mode and Desktop Mode).
Web UI: `https://<host>:47990`.

## Upgrade

Bump `POLARIS_VERSION` and `POLARIS_SHA256` in `polaris/Containerfile`, then:

```sh
systemctl --user restart polaris-build polaris
```

## How it fits together

- **Display.** `ExecStartPre` writes `$XDG_RUNTIME_DIR/polaris-display.env`:
  `gamescope-0` when a gamescope process is running (Game Mode), otherwise the
  user manager's `WAYLAND_DISPLAY`/`DISPLAY` (Desktop Mode). `PartOf=` restarts
  Polaris on a Game Mode / Desktop Mode switch so this is re-read.
- **Steam.** Steam stays on the host. The container's `/usr/bin/steam` runs the
  host's Steam via `systemd-run --user`, forwarding `WAYLAND_DISPLAY`, `DISPLAY`,
  `POLARIS_*` and `SDL_*` so Private Stream launches land on Polaris's labwc.
  It lives in `/usr/bin` because Private Stream runs commands with
  `PATH=/usr/bin:/bin`.
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
