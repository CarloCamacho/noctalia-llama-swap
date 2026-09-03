# Draft PR: Add carlocamacho/llama-swap

> Target: https://github.com/noctalia-dev/community-plugins → new PR against `main`.
> Mechanics: fork the repo, create a branch containing exactly one new top-level
> directory `llama-swap/` (copy the `llama-swap/` dir from
> https://github.com/CarloCamacho/noctalia-llama-swap — plugin.toml, the four
> .luau entries, translations/en.json, README.md, thumbnail.webp, LICENSE).
> Do NOT include catalog.toml (CI generates it). Open as **Draft** first if you
> haven't tested on a second compositor yet; the template bot closes PRs that
> lose the template structure, so keep the marker comments until all boxes are
> truthy.

---

## Plugin

- **Id:** `carlocamacho/llama-swap`
- [x] New plugin
- [ ] Update to an existing plugin (version bumped in `plugin.toml`)

## What it does

llama-swap adds a `cpu` glyph to the Noctalia bar that mirrors the live state
of a [llama-swap](https://github.com/mostlygeek/llama-swap) server: green when
a model is ready and serving, amber while a model loads, blue when idle, red
when the server is unreachable or authentication fails. The loaded model's
name can be shown next to the glyph.

Clicking the glyph opens a manager panel with:

- a summary line (last request throughput, total requests, total output tokens
  since server start)
- a rolling sparkline of output tokens per request over the last 24 *real*
  requests — health-check pings under 5 output tokens are filtered out, and
  values are min/max-normalized so small requests stay visible next to large
  ones
- the three most recent requests with throughput, model, latency and age
- every model configured in llama-swap with one-click load (warms the model
  via `GET /upstream/{id}/v1/models`, the same call llama-swap's own web UI
  makes) and unload (`POST /api/models/unload/{id}`); model IDs containing
  slashes are handled

Right-clicking the glyph opens the plugin settings. A background service polls
the server on a configurable interval (default 5s) and publishes state to the
widget and panel.

## External dependencies

None. The plugin is self-contained: all communication is HTTP against the
llama-swap server via Noctalia's runtime HTTP API. No commands are spawned, no
files are read or written, and no state is persisted outside the shell's
in-memory shared state.

**Network activity (complete list):** the poller issues four GETs per refresh
interval against the configured server — `/v1/models`, `/running`,
`/api/metrics/stats`, `/api/metrics/activity?limit=100` — plus one-off load
(`GET /upstream/{id}/v1/models`) and unload (`POST /api/models/unload/{id}`)
calls when the user clicks. The default target is
`http://localhost:8080`; the user can point it at any llama-swap host and set
a Bearer API key in settings. Nothing else is contacted.

## Testing

Exercised daily on a live llama-swap server (v175+) driving llama.cpp
llama-server instances:

- Widget: glyph color transitions verified across idle → loading → ready →
  unreachable (server stopped/started) and auth-failed (wrong API key).
- Panel: opened via bar click and via
  `noctalia msg panel-toggle carlocamacho/llama-swap:manager`; summary, sparkline,
  recent requests and model list all render from live data.
- Load/unload: loaded and unloaded models (including a model id without
  slashes and a config containing multiple models); spinner shows while a load
  is pending, inline `loaded` label appears when ready; unload stops the
  llama-server process as observed in llama-swap logs.
- Settings: server URL, API key, refresh interval (3–120 clamped) and
  show-loaded-model toggle all take effect on change.
- Load-timeout notification fires when a model does not reach ready within
  3 minutes.

- [ ] Tested on Niri
- [x] Tested on Hyprland
- [ ] Tested on Sway
- **Noctalia version tested against:** v5.0.0 (5.0.0_beta.10-1-dirty, CachyOS package `cachyos-hypr-noctalia`)
- **Plugin API level:** 28

## Screenshots / Videos

- Thumbnail (960×540, official generator): `llama-swap/thumbnail.webp` — shows
  the live panel with real data.
- Live panel capture while a model is loaded and requests are flowing:

![llama-swap panel running with live data](https://raw.githubusercontent.com/CarloCamacho/noctalia-llama-swap/main/llama-swap/thumbnail.webp)

<!-- Replace/append with a screencap or short video link from your own setup
     before submitting — the template requires visual evidence for anything
     with a visual surface. -->

## Checklist

- [x] The directory name matches the part of `id` after the `/` in `plugin.toml` exactly.
- [x] It ships `plugin.toml`, `README.md`, `thumbnail.webp`, and `translations/en.json`.
- [x] `README.md` follows the
      [README template](https://github.com/noctalia-dev/community-plugins/blob/main/README_TEMPLATE.md), documents
      every entry id and dependency, and includes exact panel IPC commands and launcher prefixes where applicable.
- [x] I created `thumbnail.webp` with the [thumbnail generator](https://assets.noctalia.dev/plugins/thumbnail-generator.html).
- [x] `version` follows semver and is bumped in this PR; `plugin_api` is the oldest API level this plugin requires.
- [x] Every non-English translation in this PR uses a locale supported by Noctalia core, and I can read, write, and
      understand that language well enough to review and maintain it (no unreviewed machine/LLM translations).
      *(en.json only.)*
- [x] I did not edit `catalog.toml`; CI generates it.
- [x] This PR touches exactly one plugin directory.

## Code review attestation

- [x] The code is readable and not obfuscated, minified, or generated.
      *(Four hand-written Luau files, commented, ~700 lines total.)*
- [x] It does not download and execute remote code.
- [x] Every network call, filesystem write, and spawned process is something the description above accounts for.
      *(Network calls enumerated under External dependencies; no filesystem access; no process spawning.)*
- [x] I have the right to publish this code under the `license` declared in `plugin.toml`. *(MIT, © CarloCamacho.)*
