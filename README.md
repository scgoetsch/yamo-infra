# yamo-infra

Deployment and operations tooling for the YAMO stack.

## Repository layout

```
yamo-infra/           ← this repo
yamo-os/              ← Node.js agentic kernel
yamo-bridge/          ← Elixir/Phoenix coordination plane
yamo-memory-mesh/     ← optional: only needed for local development
```

All four repos must be cloned as siblings in the same parent directory.

## Prerequisites

- Docker + Docker Compose v2
- [overmind](https://github.com/DarthSim/overmind) (for local `make dev` workflow)
- Erlang/OTP 27 + Elixir 1.19 via [asdf](https://asdf-vm.com) (local dev only)
- Node.js 22+ (local dev only)

## Quick start (Docker)

```bash
# 1. Clone repos
git clone https://github.com/scgoetsch/yamo-infra
git clone https://github.com/scgoetsch/yamo-os
git clone https://github.com/scgoetsch/yamo-bridge
cd yamo-infra

# 2. Configure environment
cp .env.example .env
# Edit .env — set at least one LLM key and YAMO_BRIDGE_SECRET_KEY_BASE:
#   openssl rand -hex 64   → paste into YAMO_BRIDGE_SECRET_KEY_BASE

# 3. Build and start
make docker-build
make docker-up
```

Services will be available at:
- `http://localhost:4001`  — yamo-bridge
- `http://localhost:18790` — yamo-os daemon
- `http://localhost:3000`  — Grafana (admin / admin)
- `http://localhost:9090`  — Prometheus

## Local development (overmind)

```bash
make dev-bg     # start bridge + daemon in background
make status     # show health and PIDs
make logs       # tail both logs
make stop       # graceful shutdown + cleanup
make restart    # stop then start
```

## 3-node Raft cluster (Docker)

```bash
docker compose -f docker-compose.yml -f docker-compose.cluster.yml up -d
```

## Make targets

| Target | Description |
|--------|-------------|
| `dev-bg` | Start bridge + daemon via overmind (background) |
| `dev` | Start via overmind (foreground, multiplexed logs) |
| `stop` | Stop all services, clean up socket + Ra data |
| `restart` | Stop then start |
| `status` | Show PIDs and health for both services |
| `logs` | Tail both logs |
| `logs-bridge` | Tail bridge log only |
| `logs-daemon` | Tail daemon log only |
| `docker-build` | Build all Docker images |
| `docker-up` | Start full Docker stack (bridge + daemon + observability) |
| `docker-down` | Stop Docker stack (keeps volumes) |
| `docker-status` | Show Docker container status |
| `install-skills` | Sync yamo-skills into `~/.claude/skills/` |
