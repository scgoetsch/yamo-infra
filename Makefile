INFRA_DIR  := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
WORKSPACE  := $(abspath $(INFRA_DIR)..)/
BRIDGE_DIR := $(WORKSPACE)yamo-bridge
DAEMON_DIR := $(WORKSPACE)yamo-os

BRIDGE_PID  := /tmp/yamo-bridge.pid
DAEMON_PID  := /tmp/yamo-daemon.pid
BRIDGE_LOG  := /tmp/yamo-bridge.log
DAEMON_LOG  := /tmp/yamo-daemon.log
BRIDGE_PORT := 4001
DAEMON_PORT := 18790

OVERMIND    := $(HOME)/.local/bin/overmind
OVERMIND_SOCK := $(INFRA_DIR).overmind.sock
RA_DATA_DIR := /tmp/yamo_ra_data
ENV_FILE    := $(INFRA_DIR).env

SKILLS_SRC  := $(WORKSPACE)yamo-skills/skills/utility
SKILLS_DEST := $(HOME)/.claude/skills

.PHONY: dev dev-bg bridge daemon stop restart status logs logs-bridge logs-daemon \
        docker-build docker-up docker-down docker-status install-skills help

## Start bridge + daemon together via overmind (multiplexed logs, graceful stop)
dev:
	@if $(OVERMIND) status -D $(WORKSPACE) 2>/dev/null | grep -q "running"; then \
		echo "==> Already running — use 'make status' to inspect, 'make restart' to restart."; \
		$(MAKE) --no-print-directory status; \
	else \
		echo "==> Loading env and starting services via overmind..."; \
		test -f $(ENV_FILE) && set -a && . $(ENV_FILE) && set +a || true; \
		cd $(WORKSPACE) && $(OVERMIND) start; \
	fi

## Start bridge + daemon in background (detached), loading .env
dev-bg:
	@if [ -S $(OVERMIND_SOCK) ] && $(OVERMIND) status -s $(OVERMIND_SOCK) 2>/dev/null | grep -q "running"; then \
		echo "==> Already running — use 'make status'."; \
	else \
		rm -f $(OVERMIND_SOCK); \
		echo "==> Starting in background..."; \
		test -f $(ENV_FILE) && set -a && . $(ENV_FILE) && set +a || true; \
		cd $(WORKSPACE) && $(OVERMIND) start -D; \
		$(MAKE) --no-print-directory _wait-bridge; \
		$(MAKE) --no-print-directory _wait-daemon; \
		echo "==> All services healthy."; \
		$(MAKE) --no-print-directory status; \
	fi

## Start only the bridge (background, PID-managed)
bridge:
	@$(MAKE) --no-print-directory _bridge-start

## Start only the daemon (background, PID-managed, waits for bridge to be healthy)
daemon:
	@$(MAKE) --no-print-directory _bridge-check
	@$(MAKE) --no-print-directory _daemon-start

## Stop all services (graceful SIGTERM, fallback SIGKILL)
stop:
	@if [ -S $(OVERMIND_SOCK) ] && $(OVERMIND) status -s $(OVERMIND_SOCK) 2>/dev/null | grep -q "running"; then \
		echo "==> Stopping via overmind..."; \
		$(OVERMIND) stop -s $(OVERMIND_SOCK); \
	else \
		$(MAKE) --no-print-directory _daemon-stop; \
		$(MAKE) --no-print-directory _bridge-stop; \
	fi
	@rm -f $(OVERMIND_SOCK)
	@rm -rf $(RA_DATA_DIR)
	@echo "==> Cleaned up overmind socket and Ra data."

## Stop then start all services
restart: stop
	@sleep 1
	@$(MAKE) --no-print-directory dev-bg

## Show running status, PIDs, and bound ports
status:
	@echo ""
	@echo "  bridge  $(shell \
		if [ -f $(BRIDGE_PID) ] && kill -0 $$(cat $(BRIDGE_PID)) 2>/dev/null; then \
			echo "running  pid=$$(cat $(BRIDGE_PID))  port=$(BRIDGE_PORT)"; \
		elif pgrep -f "[m]ix run --no-halt" > /dev/null 2>&1; then \
			echo "running  pid=$$(pgrep -f '[m]ix run --no-halt' | head -1)  port=$(BRIDGE_PORT)  (no pidfile)"; \
		else \
			echo "stopped"; \
		fi)"
	@echo "  daemon  $(shell \
		if [ -f $(DAEMON_PID) ] && kill -0 $$(cat $(DAEMON_PID)) 2>/dev/null; then \
			echo "running  pid=$$(cat $(DAEMON_PID))  port=$(DAEMON_PORT)"; \
		elif pgrep -f "[t]sx bin/daemon.ts" > /dev/null 2>&1; then \
			echo "running  pid=$$(pgrep -f '[t]sx bin/daemon.ts' | head -1)  port=$(DAEMON_PORT)  (no pidfile)"; \
		else \
			echo "stopped"; \
		fi)"
	@echo ""
	@echo "  health  bridge: $(shell curl -sf http://localhost:$(BRIDGE_PORT)/health > /dev/null 2>&1 && echo "ok" || echo "unreachable")"
	@echo "  health  daemon: $(shell curl -sf http://localhost:$(DAEMON_PORT)/health > /dev/null 2>&1 && echo "ok" || echo "unreachable")"
	@echo ""

## Tail both logs
logs:
	@tail -f $(BRIDGE_LOG) $(DAEMON_LOG) 2>/dev/null || echo "No log files found — use 'make dev-bg' to capture logs"

## Tail bridge log only
logs-bridge:
	@tail -f $(BRIDGE_LOG)

## Tail daemon log only
logs-daemon:
	@tail -f $(DAEMON_LOG)

## Build all Docker images (bridge + daemon)
docker-build:
	docker compose build

## Start full stack in Docker (bridge + daemon + prometheus + grafana)
docker-up:
	docker compose up -d
	@echo "==> Services starting. Ports: bridge=4001  daemon=18790  grafana=3000  prometheus=9090"

## Stop and remove Docker containers (keeps volumes)
docker-down:
	docker compose down

## Show Docker container status and health
docker-status:
	docker compose ps

## Sync skills from yamo-skills git repo into ~/.claude/skills/ (Claude Code skill registry)
install-skills:
	@echo "==> Installing skills from $(SKILLS_SRC) → $(SKILLS_DEST)"
	@mkdir -p $(SKILLS_DEST)
	@rsync -a --delete $(SKILLS_SRC)/yamo-unified-os/ $(SKILLS_DEST)/yamo-super/
	@echo "  yamo-super (yamo-unified-os) → $(SKILLS_DEST)/yamo-super/"
	@rsync -a --delete $(SKILLS_SRC)/research-driven-dev/ $(SKILLS_DEST)/research-driven-dev/
	@echo "  research-driven-dev          → $(SKILLS_DEST)/research-driven-dev/"
	@rsync -a --delete $(SKILLS_SRC)/modular-translator/ $(SKILLS_DEST)/modular-translator/
	@echo "  modular-translator           → $(SKILLS_DEST)/modular-translator/"
	@echo "==> Done. Restart Claude Code for changes to take effect."

help:
	@echo ""
	@echo "  Usage: make <target>"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
	@echo ""


# ── Internal targets ─────────────────────────────────────────────────────────

_bridge-start:
	@if [ -f $(BRIDGE_PID) ] && kill -0 $$(cat $(BRIDGE_PID)) 2>/dev/null; then \
		echo "==> bridge already running (pid $$(cat $(BRIDGE_PID)))"; \
	else \
		echo "==> Starting bridge..."; \
		cd $(BRIDGE_DIR) && MIX_ENV=dev mix run --no-halt >> $(BRIDGE_LOG) 2>&1 & echo $$! > $(BRIDGE_PID); \
		$(MAKE) --no-print-directory _wait-bridge; \
	fi

_daemon-start:
	@if [ -f $(DAEMON_PID) ] && kill -0 $$(cat $(DAEMON_PID)) 2>/dev/null; then \
		echo "==> daemon already running (pid $$(cat $(DAEMON_PID)))"; \
	else \
		echo "==> Starting daemon..."; \
		test -f $(ENV_FILE) && set -a && . $(ENV_FILE) && set +a || true; \
		cd $(DAEMON_DIR) && npm exec tsx bin/daemon.ts >> $(DAEMON_LOG) 2>&1 & echo $$! > $(DAEMON_PID); \
		$(MAKE) --no-print-directory _wait-daemon; \
	fi

_bridge-stop:
	@if [ -f $(BRIDGE_PID) ] && kill -0 $$(cat $(BRIDGE_PID)) 2>/dev/null; then \
		echo "==> Stopping bridge (pid $$(cat $(BRIDGE_PID)))..."; \
		kill $$(cat $(BRIDGE_PID)) 2>/dev/null; \
		for i in 1 2 3 4 5; do \
			kill -0 $$(cat $(BRIDGE_PID)) 2>/dev/null || break; sleep 1; \
		done; \
		kill -9 $$(cat $(BRIDGE_PID)) 2>/dev/null || true; \
		rm -f $(BRIDGE_PID); \
		echo "==> Bridge stopped."; \
	else \
		pkill -TERM -f "[m]ix run --no-halt" 2>/dev/null && echo "==> Bridge stopped." || echo "==> Bridge not running."; \
		rm -f $(BRIDGE_PID); \
	fi

_daemon-stop:
	@if [ -f $(DAEMON_PID) ] && kill -0 $$(cat $(DAEMON_PID)) 2>/dev/null; then \
		echo "==> Stopping daemon (pid $$(cat $(DAEMON_PID)))..."; \
		kill $$(cat $(DAEMON_PID)) 2>/dev/null; \
		for i in 1 2 3 4 5; do \
			kill -0 $$(cat $(DAEMON_PID)) 2>/dev/null || break; sleep 1; \
		done; \
		kill -9 $$(cat $(DAEMON_PID)) 2>/dev/null || true; \
		rm -f $(DAEMON_PID); \
		echo "==> Daemon stopped."; \
	else \
		pkill -TERM -f "[t]sx bin/daemon.ts" 2>/dev/null && echo "==> Daemon stopped." || echo "==> Daemon not running."; \
		rm -f $(DAEMON_PID); \
	fi

_bridge-check:
	@if ! curl -sf http://localhost:$(BRIDGE_PORT)/health > /dev/null 2>&1; then \
		echo "==> Bridge not healthy — start it first with 'make bridge'"; exit 1; \
	fi

# Poll bridge health up to 90s (non-fatal — bridge is optional)
# Ra/OTP initialization takes ~20s on cold start; allow extra headroom for mix compilation.
_wait-bridge:
	@echo "==> Waiting for bridge on :$(BRIDGE_PORT)..."; \
	for i in $$(seq 1 90); do \
		curl -sf http://localhost:$(BRIDGE_PORT)/health > /dev/null 2>&1 && echo "==> Bridge healthy." && exit 0; \
		sleep 1; \
	done; \
	echo "==> Bridge not ready after 90s — continuing without it (daemon runs in local-only mode)"

# Poll daemon health up to 30s
_wait-daemon:
	@echo "==> Waiting for daemon on :$(DAEMON_PORT)..."; \
	for i in $$(seq 1 30); do \
		curl -sf http://localhost:$(DAEMON_PORT)/health > /dev/null 2>&1 && echo "==> Daemon healthy." && exit 0; \
		sleep 1; \
	done; \
	echo "==> Daemon did not become healthy in 30s — check $(DAEMON_LOG)"; exit 1
