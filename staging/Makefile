# Staging control plane for darmawan.be — run from the Mac, acts on the EC2
# instance over SSH. Nothing here is pushed to git; the repo stays local and
# rsync is the "push" mechanism.
#
# First bring-up:   make check bootstrap secrets caddy
#                   make deploy          # naikbusaja then maribelanja, in order
# Redeploy one app: make naikbusaja      /  make maribelanja
# Shell on the box: make ssh
#
# App sources (override with make VAR=...):
#   NAIKBUSAJA_DIR  /Users/jeffdarmawan/projects/naikbusaja
#   MARIBELANJA_DIR /Users/jeffdarmawan/projects/elixir/github.com/jeffdarmawan/maribelanja

HOST           ?= ubuntu@47.131.158.206
KEY            ?= $(abspath ../.ssh/darmawan-be-staging.pem)
IP             ?= $(lastword $(subst @, ,$(HOST)))
SSH            = ssh -i $(KEY) $(HOST)
RSYNC          = rsync -az --delete -e "ssh -i $(KEY)"

NAIKBUSAJA_DIR  ?= /Users/jeffdarmawan/projects/naikbusaja
MARIBELANJA_DIR ?= /Users/jeffdarmawan/projects/elixir/github.com/jeffdarmawan/maribelanja

# rsync excludes for app source syncs: the server keeps its build artifacts
# (excluded from both transfer and deletion), and the deploy-file exclusions
# protect the server's .env / compose from --delete (they are copied
# explicitly right after).
APP_EXCLUDES = --exclude .git --exclude .DS_Store --exclude _build --exclude deps \
               --exclude node_modules --exclude .env --exclude docker-compose.staging.yml

CADDY_EXCLUDES = --exclude .DS_Store --exclude .dev-bcrypt --exclude dev-auth-credentials.txt

.PHONY: help check bootstrap secrets caddy naikbusaja maribelanja deploy ssh \
        ps logs-caddy logs-naikbusaja logs-maribelanja

help:
	@echo "make check          - SSH reachability + docker + port 80/443 state"
	@echo "make bootstrap      - install docker on the server, /opt dirs, proxy network"
	@echo "make secrets        - generate .env files + caddy basic auth on the server"
	@echo "make caddy          - deploy the shared reverse proxy (auto Let's Encrypt)"
	@echo "make naikbusaja     - build + deploy naikbusaja.darmawan.be"
	@echo "make maribelanja    - build + deploy maribelanja.darmawan.be"
	@echo "make deploy         - naikbusaja then maribelanja (one build at a time)"
	@echo "make ssh            - shell on the staging box"
	@echo "make ps             - container status for all three stacks"
	@echo "make logs-caddy | logs-naikbusaja | logs-maribelanja"

check:
	@echo "== ssh =="
	@$(SSH) 'echo "connected: $$(uname -m), docker: $$(command -v docker >/dev/null && docker --version || echo MISSING)"'
	@echo "== ports =="
	@python3 scripts/check-ports.py $(IP)

bootstrap:
	$(SSH) 'bash -s' < scripts/bootstrap-server.sh

secrets:
	$(SSH) 'bash -s' < scripts/gen-secrets.sh

# rsync resets the Caddyfile placeholder, then the hash is (re-)applied.
caddy: secrets
	$(RSYNC) $(CADDY_EXCLUDES) caddy/ $(HOST):/opt/caddy/
	$(SSH) 'test -f /opt/caddy/.dev-bcrypt || { echo "missing /opt/caddy/.dev-bcrypt — run make secrets"; exit 1; }; \
	  sed -i "s|__NAIKBUSAJA_DEV_BCRYPT__|$$(cat /opt/caddy/.dev-bcrypt)|" /opt/caddy/Caddyfile; \
	  cd /opt/caddy && docker compose up -d && docker compose ps'
	@echo "caddy up — watch cert issuance: make logs-caddy"

naikbusaja:
	$(RSYNC) $(APP_EXCLUDES) $(NAIKBUSAJA_DIR)/ $(HOST):/opt/naikbusaja/
	$(RSYNC) apps/naikbusaja/docker-compose.staging.yml $(HOST):/opt/naikbusaja/docker-compose.staging.yml
	$(SSH) 'test -f /opt/naikbusaja/.env || { echo "missing /opt/naikbusaja/.env — run make secrets"; exit 1; }; \
	  cd /opt/naikbusaja && docker compose -f docker-compose.staging.yml up -d --build && \
	  docker compose -f docker-compose.staging.yml ps'
	@echo "naikbusaja deployed — first boot migrates + imports the transit feed: make logs-naikbusaja"

maribelanja:
	$(RSYNC) $(APP_EXCLUDES) $(MARIBELANJA_DIR)/ $(HOST):/opt/maribelanja/
	$(RSYNC) apps/maribelanja/docker-compose.staging.yml $(HOST):/opt/maribelanja/docker-compose.staging.yml
	$(SSH) 'test -f /opt/maribelanja/.env || { echo "missing /opt/maribelanja/.env — run make secrets"; exit 1; }; \
	  cd /opt/maribelanja && docker compose -f docker-compose.staging.yml up -d --build && \
	  docker compose -f docker-compose.staging.yml ps'
	@echo "maribelanja deployed — mail: ssh -L 8025:127.0.0.1:8025 $(HOST) → http://localhost:8025"

deploy: naikbusaja maribelanja

ssh:
	$(SSH)

ps:
	$(SSH) 'cd /opt/caddy && echo "== caddy ==" && docker compose ps; \
	  cd /opt/naikbusaja && echo "== naikbusaja ==" && docker compose -f docker-compose.staging.yml ps; \
	  cd /opt/maribelanja && echo "== maribelanja ==" && docker compose -f docker-compose.staging.yml ps'

logs-caddy:
	$(SSH) 'cd /opt/caddy && docker compose logs -f --tail 50 caddy'

logs-naikbusaja:
	$(SSH) 'cd /opt/naikbusaja && docker compose -f docker-compose.staging.yml logs -f --tail 50'

logs-maribelanja:
	$(SSH) 'cd /opt/maribelanja && docker compose -f docker-compose.staging.yml logs -f --tail 50'
