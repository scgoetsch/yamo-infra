# Deployment Guide

## Architecture

The YAMO stack consists of three repos that must be cloned as siblings:

```
parent-dir/
├── yamo-infra/    ← this repo (Makefile, Docker Compose, monitoring)
├── yamo-os/       ← Node.js agentic kernel (port 18790)
└── yamo-bridge/   ← Elixir/Phoenix coordination plane (port 4001)
```

### Component roles

| Component | Language | Role |
|-----------|----------|------|
| **yamo-os** | Node.js / TypeScript | LLM execution, semantic memory (LanceDB), skill evolution, WebSocket API |
| **yamo-bridge** | Elixir / Phoenix | Agent registration, Raft consensus, cross-kernel skill routing, memory federation |
| **yamo-infra** | Makefile / Docker | Orchestration, observability (Prometheus + Grafana) |

### Network topology

```
Clients (Telegram / OpenClaw / API)
          │
          ▼
  yamo-os daemon  :18790   ← YamoGateway HTTP + WebSocket
          │
          │  WebSocket  ws://bridge:4001/socket/websocket
          ▼
  yamo-bridge     :4001    ← Phoenix channels, Raft leader
          │
          │  (optional 3-node cluster)
  bridge2 :4002 / bridge3 :4003

Observability:
  Prometheus  :9090   scrapes :4001/metrics + :18790/metrics
  Grafana     :3000   dashboards: YAMO Bridge, YAMO Ingest
```

---

## Prerequisites

### Docker deployment
- Docker Engine 24+
- Docker Compose v2

### Local development
- [overmind](https://github.com/DarthSim/overmind) — `brew install overmind` or download binary
- Erlang/OTP 27 + Elixir 1.19 via [asdf](https://asdf-vm.com)
- Node.js 22+

---

## Environment variables

Copy `.env.example` to `.env` and fill in your values.

### Required

| Variable | Description |
|----------|-------------|
| `YAMO_BRIDGE_SECRET_KEY_BASE` | 64-char random string for Phoenix session signing. Generate: `openssl rand -hex 64` |
| At least one of: `ZAI_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` | LLM provider API key |

### LLM provider

| Variable | Default | Description |
|----------|---------|-------------|
| `ZAI_API_KEY` | — | z.ai API key |
| `OPENAI_API_KEY` | — | OpenAI API key |
| `ANTHROPIC_API_KEY` | — | Anthropic API key |
| `LLM_PROVIDER` | `zai` | Active provider: `zai \| openai \| anthropic \| ollama` |
| `LLM_MODEL` | _(provider default)_ | Override model name |
| `LLM_BASE_URL` | _(provider default)_ | Override base URL (e.g. local vLLM endpoint) |

### Bridge

| Variable | Default | Description |
|----------|---------|-------------|
| `YAMO_BRIDGE_AUTH_ENABLED` | `false` | Enable Ed25519 device authentication (RFC-0008) |
| `RELEASE_COOKIE` | `yamo-cluster-secret-changeme` | Shared Erlang cookie for multi-node cluster — **change in production** |

### Optional features

| Variable | Default | Description |
|----------|---------|-------------|
| `YAMO_SRE_ENABLED` | `false` | Enable autonomous SRE alert correlation agent |
| `YAMO_SLACK_WEBHOOK_URL` | — | Slack webhook for SRE alert notifications |
| `YAMO_PD_API_KEY` | — | PagerDuty API key for SRE incident notes |
| `YAMO_INBOX_DIR` | — | Directory to watch for auto-ingest (e.g. `~/.yamo/inbox`) |

### Observability

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAFANA_PASSWORD` | `admin` | Grafana admin password |
| `LOG_LEVEL` | `info` | Log verbosity: `quiet \| info \| verbose \| debug` |

### Embeddings

| Variable | Default | Description |
|----------|---------|-------------|
| `EMBEDDING_MODEL_TYPE` | `local` | `local` (ONNX, no API key) or `openai` |
| `EMBEDDING_MODEL_NAME` | `Xenova/all-MiniLM-L6-v2` | Embedding model identifier |
| `EMBEDDING_DIMENSION` | `384` | Vector dimension (must match model) |

---

## Local development

```bash
make dev-bg     # start bridge + daemon in background via overmind
make status     # show PIDs and health
make logs       # tail both logs (bridge + daemon interleaved)
make stop       # graceful shutdown — also cleans up overmind socket + Ra data
make restart    # stop then start
```

**Note:** `make stop` clears Ra/OTP data from `/tmp/yamo_ra_data`. This is intentional — stale Ra state causes the bridge to silently fail to bind port 4001 on restart.

---

## Docker deployment

```bash
# Build images (run from yamo-infra/ with siblings present)
make docker-build

# Start full stack: bridge + daemon + Prometheus + Grafana
make docker-up

# Bridge + daemon only (no observability)
docker compose up bridge daemon

# Check status
make docker-status

# Stop (keeps volumes — LanceDB data and Ra state are preserved)
make docker-down
```

Services:
- `http://localhost:4001`  — yamo-bridge
- `http://localhost:18790` — yamo-os daemon
- `http://localhost:3000`  — Grafana (admin / `$GRAFANA_PASSWORD`)
- `http://localhost:9090`  — Prometheus

---

## 3-node Raft cluster

```bash
docker compose -f docker-compose.yml -f docker-compose.cluster.yml up -d
```

This starts `bridge`, `bridge2`, `bridge3` — all sharing `RELEASE_COOKIE` and auto-discovering each other via `libcluster`. The first alphabetical node triggers the Raft election. Set `RELEASE_COOKIE` to a secret value in production.

---

## Persistent storage

| Data | Location | Notes |
|------|----------|-------|
| LanceDB (memory) | `daemon_lancedb` Docker volume → `/app/runtime/data` | Persists across restarts; do not mount to a shared NFS path |
| Ra/Raft state | `bridge_ra_data` Docker volume → `/data/ra` | Persists cluster membership; cleared on `make stop` in local dev |
| Grafana dashboards | `grafana_data` Docker volume | Auto-provisioned from `monitoring/grafana/` |
| Prometheus metrics | `prometheus_data` Docker volume | 7-day retention by default |

---

## Troubleshooting

**Bridge port 4001 not binding**
Ra/OTP initialisation takes 20–25s on cold start. The `_wait-bridge` target polls for 90s. If it still fails, run `make stop` (clears Ra data) then `make dev-bg`.

**Daemon exits immediately with `API key missing`**
The active provider's API key is not set. Check `.env` has the correct key for `LLM_PROVIDER`.

**`@yamo/memory-mesh` not found (Docker)**
Ensure you are building from `yamo-infra/` (`make docker-build`) — the Dockerfile uses `../yamo-os` context so the published npm package is installed rather than a local symlink.

**`YAMO_BRIDGE_SECRET_KEY_BASE is missing`**
Generate one: `openssl rand -hex 64` and add to `.env`.

**Grafana shows no data**
Check Prometheus targets at `http://localhost:9090/targets` — both `yamo-bridge` and `yamo-daemon` should show `UP`. If `yamo-daemon` is down, verify port 18790 is reachable from the Prometheus container.
