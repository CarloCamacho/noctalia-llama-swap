<div align="center">

# 🦙⚡ llama-swap for Noctalia

**A Noctalia v5 plugin for [llama-swap](https://github.com/mostlygeek/llama-swap) — your local LLM fleet, one click from the bar.**

[![Noctalia](https://img.shields.io/badge/Noctalia-v5-blueviolet)](https://noctalia.dev)
[![llama-swap](https://img.shields.io/badge/llama--swap-API%20compatible-brightgreen)](https://github.com/mostlygeek/llama-swap)
[![Version](https://img.shields.io/badge/version-0.2.3-orange)]()
[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)

</div>

---

## What it does

A `cpu` glyph lives in your Noctalia bar and reflects your llama-swap server in real time:

| State | Icon color | Meaning |
|---|---|---|
| Model ready | 🟢 primary | An inference model is loaded and serving |
| Loading | 🟡 warning | A model is warming up |
| Idle | 🔵 default | Server reachable, nothing loaded |
| Problem | 🔴 error | Unreachable, auth failed, or error |

Click it for the manager panel:

```
 ┌────────────────────────────────────────────┐
 │ ⚙ llama-swap                       Connected│
 │ Last request 115 tok/s · 163 req · 30.3k out│
 │ ⡁⡈⠤⡁⢕⠑⢄⠑⢄⠉⠑⢄⠑⢄⠉⠑⢄  ← output-token sparkline │
 │ output tokens, last 24 requests             │
 ├────────────────────────────────────────────┤
 │ RECENT                                      │
 │ 115 tok/s · Gemma-4-E4B · 373ms · now       │
 │ 116 tok/s · Gemma-4-E4B · 331ms · now       │
 │ 117 tok/s · Gemma-4-E4B · 273ms · now       │
 ├────────────────────────────────────────────┤
 │ ⏹ Gemma-4-E4B-Fable5-FC-v2      loaded      │
 │ ▶ Gemma-4-E4B-Publishable-FC-v1             │
 │ ▶ Qwen3.5-9B-Uncensored-CPU                 │
 │ ▶ Qwen3.8-27B-UD                            │
 │ ▶ Qwythos-9B-v2-MTP                         │
 └────────────────────────────────────────────┘
```

- **Live tok/s sparkline** — output tokens across your last 24 requests; big prompts spike, quick pings hug the floor
- **Recent requests** — three compact inline lines: throughput · model · latency · age
- **One-click load/unload** — every configured model gets a play/stop button right in the list
- **Zero-config on localhost** — defaults to `http://localhost:8080`, add an API key only if your llama-swap sets `apiKeys`

## Install

### From source (git)

```bash
# add this repo as a plugin source on your Noctalia v5 machine
noctalia msg plugins source add carlo-local path /path/to/parent/of/this-repo-clone-dir
noctalia msg plugins enable carlocamacho/llama-swap
```

> The repo root holds `catalog.toml`; the plugin itself lives in `llama-swap/`.
> Noctalia loads path sources in place — no materialization step.

### Manual

Copy (or symlink) the `llama-swap/` directory into your plugin source path, then enable via `noctalia msg plugins list` → `noctalia msg plugins enable carlocamacho/llama-swap`.

## Settings

Right-click the bar icon → Settings.

| Setting | Default | Description |
|---|---|---|
| **Server URL** | `http://localhost:8080` | Base URL of your llama-swap server |
| **API key** | *(empty)* | Only needed if llama-swap config sets `apiKeys` |
| **Refresh interval** | `5` s | Poll frequency (min 3, max 120) |
| **Show loaded model in bar** | on | Displays the ready model's name next to the glyph |

## How it works

```
┌──────────────┐   poll /v1/models · /running       ┌───────────────┐
│  service     │   /api/metrics/stats               │ shared state  │
│  (poller)    │   /api/metrics/activity            ├───────────────┤
└──────────────┘                                    │ ▸ bar widget  │
      │  POST /api/models/unload/{id}               │ ▸ panel       │
      │  GET  /upstream/{id}/v1/models  ← "load"    └───────────────┘
      ▼
   llama-swap  ──►  llama-server / vLLM / …
```

- **Load** = warm the upstream via `GET /upstream/{id}/v1/models` — exactly what llama-swap's own web UI does (there is no dedicated load endpoint). The poller watches `/v1/models` status flip to `loaded`.
- **Unload** = `POST /api/models/unload/{id}` (wildcard path — model IDs containing slashes are handled correctly).
- Panel and widget consume shared state published by the poller; UI stays responsive even while the server is slow.

## Requirements

- **Noctalia v5** (plugin_api 28) — QML-era v4 plugins are a different runtime
- A running [llama-swap](https://github.com/mostlygeek/llama-swap) server reachable from the desktop
- No external binaries — pure Luau + Noctalia HTTP

## License

[MIT](LICENSE) © CarloCamacho
