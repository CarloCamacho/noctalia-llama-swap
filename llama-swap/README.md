# llama-swap for Noctalia

A [Noctalia v5](https://noctalia.dev) plugin for [llama-swap](https://github.com/mostlygeek/llama-swap).

Bar icon shows llama-swap status at a glance (green = model ready, amber = loading, red = unreachable). Click to open a panel with:

- **tok/s summary** — p50/p95 generation throughput, total requests and output tokens
- **Recent requests** — last 6 requests with per-request tok/s, duration and tokens
- **Model list** — every configured model with a play button to load and a stop button to unload

## Setup

1. Install the plugin, then right-click the bar icon → Settings.
2. Set **Server URL** to your llama-swap server (default `http://localhost:8080`).
3. If your llama-swap config sets `apiKeys`, paste one into **API key**. Otherwise leave empty (localhost only).

## Notes

- Loading a model warms it via llama-swap's `/upstream/{id}/v1/models` endpoint — the same thing the built-in web UI does; there is no dedicated load endpoint.
- Unloading uses `POST /api/models/unload/{id}` (handles model IDs containing slashes).
- The poller refreshes every `refresh_interval` seconds (default 5s, min 3s).

## License

MIT
