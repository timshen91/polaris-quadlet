# polaris-quadlet

[Polaris](https://github.com/papi-ux/polaris) (a Sunshine fork) as a rootless
podman Quadlet on SteamOS. Everything lives under `~`; the read-only root is never
unlocked.

Polaris is built from upstream source with this repo's patches, and the image is
published to `ghcr.io/timshen91/polaris-quadlet` by CI; the host only pulls it.

Tested on SteamOS 3.9 with an AMD GPU (Strix Halo) and Polaris 1.4.13; an
earlier revision was tested on Intel. NVIDIA is not covered (no CUDA build).

## Files

Install into `~/.config/containers/systemd/`:

| File | Purpose |
|---|---|
| `polaris.container` | Runs the published image: host network, host PID (Game Mode detection), `/dev/dri`, `/dev/uinput`, the user runtime dir (PipeWire, gamescope sockets, session bus). |
| `polaris-config.volume` | Named volume for Polaris settings, credentials and pairings. |

Also used: named volumes `polaris-cache` (`~/.cache`) and `polaris-labwc`
(`~/.config/labwc-polaris`), created automatically.

The image (not installed on the host):

| File | Purpose |
|---|---|
| `polaris/Containerfile` | Builds Polaris from a pinned upstream commit, as upstream CI builds its Arch package, then installs it on Arch Linux with Intel/AMD VAAPI and Vulkan userspace and gamescope (so Gamescope Stream is offered). |
| `polaris/patches/` | Patches applied to upstream, one commit each (`git am`). |
| `polaris/polaris-gamescope-session` | Installed as Polaris's Gamescope Stream helper; see below. |
| `polaris/steam-forward.sh` | Installed as the container's `/usr/bin/steam`; forwards to the host's Steam. |

## Install

```sh
mkdir -p ~/.config/containers/systemd
cp polaris.container polaris-config.volume ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start polaris
```

It starts via `xdg-desktop-autostart.target` (Desktop Mode) and
`default.target` (at boot; enable lingering with `loginctl enable-linger`).
Web UI: `https://<host>:47990`.

Host-specific settings go in a drop-in, e.g.
`~/.config/containers/systemd/polaris.container.d/local.conf`.

## Upgrade

Pull the new image and restart:

```sh
podman pull ghcr.io/timshen91/polaris-quadlet:latest
systemctl --user restart polaris
```

To move to a new Polaris version, bump `POLARIS_REF`/`POLARIS_COMMIT` in
`polaris/Containerfile` and check the patches still apply. The *Upstream watch*
workflow keeps an issue up to date with upstream Polaris releases and the state
of the upstream fixes our patches wait for.

## Patches

| Patch | Why |
|---|---|
| `0001` Gamescope Stream without a portal | Gamescope Stream captures gamescope's own PipeWire node, but Polaris still required a desktop ScreenCast portal before probing encoders, so a host with no desktop session refused every launch. |
| `0002` Resume sees the resuming client | State commands (run on resume) got the launching client's `POLARIS_CLIENT_*` mode, so a client reconnecting at another resolution could not resize anything for itself. |

## Fake display: stock Game Mode at the client's resolution

Streams stock SteamOS Game Mode, but on a fake monitor sized for the client
instead of the internal panel, captured from gamescope's PipeWire stream as
usual (native touch included, since Game Mode reads input devices):

- Launch plugs a fake display into an unused HDMI connector at the client's
  mode. Game Mode prefers external displays, so it moves there and the panel
  goes dark.
- A client resuming or relaunching at another mode only changes the fake
  display's mode, before the session's capture starts; Steam and the running
  game stay up.
- Ending the session starts a 15 minute countdown
  (`polaris-fake-display-idle.timer`); the next stream cancels it. Only when
  it runs out does the fake display go away and Game Mode return to the panel.
- A mode the fake display cannot carry (over 340 MHz: above that HDMI needs a
  scrambling handshake no fake display can answer) falls back to the same size
  at a lower refresh rate (down to 60 Hz), then the same aspect ratio, smaller;
  Polaris scales to the client.

On amdgpu, driving a connector with nothing attached works, but switching
between it and the internal panel is where the display firmware (Panel
Replay) and page flips misbehaved, and a compositor torn down mid-flip on it
could leave a CRTC unable to flip until a reboot. Hence the countdown, and a
drop-in that unplugs before Game Mode's gamescope stops. DisplayPort
connectors are never used.

`fake-display/polaris-fake-display` does this through generic DRM: an EDID
(the mode as preferred, a 48 Hz..mode VRR range, no audio) written to debugfs
`edid_override`, the connector forced on through sysfs `status`, and a hotplug
uevent. That needs root but no kernel module and no particular driver; the
driver only has to light a connector with nothing attached (tested on amdgpu).
Polaris reaches it through two root-owned units polkit lets its user start.

Install on the host (writes under `/etc` only):

```sh
sudo fake-display/install.sh "$USER"
```

then add to Polaris's config (`polaris.conf`, or the web UI's command settings),
with `native_pen_touch = enabled` for native touch:

```
global_prep_cmd = [{"do":"polaris-fake-display plug","undo":"polaris-fake-display unplug"}]
global_state_cmd = [{"do":"polaris-fake-display plug","undo":""}]
```

To get the panel back right away: `systemctl start polaris-fake-display-unplug.service`.

## Gamescope Stream: SteamOS Game Mode, headless

With `linux_stream_mode = gamescope_stream`, Polaris runs Steam Big Picture and
Steam titles through `polaris-gamescope-session` (`start [appid]`, `wait`,
`stop`). This repo's helper replaces Polaris's nested session with SteamOS's own
Game Mode session, headless at the client's resolution and refresh rate:

- The host's `/usr/lib/steamos/gamescope-session`, with only its final
  `exec gamescope` replaced: `--backend headless` at the client's mode instead
  of the panel, and `--max-scale 1`, because gamescope places libei absolute
  pointer events (Moonlight touch) without the upscaling it applies to small
  windows. Derived at run time, so SteamOS updates to the script carry over.
- Stock `steam-launcher` (`-steamos3 -steampal -steamdeck -gamepadui`), so the
  Steam button and overlay behave as in Game Mode, plus mangoapp, and ibus and
  `steam_notif_daemon` unless a desktop already provides them.
- Each runs as a transient user unit on the host (`polaris-steamos-*`), started
  through the user manager because rootless podman cannot see host processes.
- Polaris captures that gamescope's PipeWire node and sends mouse and keyboard
  to its libei socket. A headless gamescope reads no input devices, so touch
  has to be Moonlight's mouse emulation (`native_pen_touch = disabled`).
- `stop` lets Steam exit (`steam -shutdown`) before stopping the units.
- Official Game Mode must not be running: Polaris then streams that instead,
  and Steam allows one client per user.

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
- **X11.** `/tmp/.X11-unix` is deliberately not mounted: labwc's Xwayland must own
  it, and `Network=host` already shares the host's abstract X sockets.

## Capture with VAAPI (Intel/AMD)

Polaris captures with GPU buffers (DMA-BUF) by default only for PyroWave and
CUDA; VAAPI uses a CPU copy unless `POLARIS_PORTAL_DMABUF=1` is set, which
Polaris treats as an unvalidated opt-in.
