#!/usr/bin/env bash
# Runs ON the staging server — `make secrets` pipes it over SSH.
# Generates the per-app .env files and the Caddy basic-auth hash.
# Idempotent: existing files are kept, only missing ones are written.
set -euo pipefail

command -v docker >/dev/null || { echo "docker missing — run 'make bootstrap' first"; exit 1; }
command -v openssl >/dev/null || { echo "openssl missing"; exit 1; }

# --- naikbusaja --------------------------------------------------------------
if [ -f /opt/naikbusaja/.env ]; then
  echo "naikbusaja .env already present — keeping it"
else
  # base64 has no '$' chars, so it is safe inside a compose .env file.
  SKB=$(openssl rand -base64 48)
  {
    echo "SECRET_KEY_BASE=$SKB"
    echo "PHX_HOST=naikbusaja.darmawan.be"
    echo "PHX_SCHEME=https"
  } > /opt/naikbusaja/.env
  chmod 600 /opt/naikbusaja/.env
  echo "naikbusaja .env written (SECRET_KEY_BASE generated)"
fi

# --- maribelanja -------------------------------------------------------------
if [ -f /opt/maribelanja/.env ]; then
  echo "maribelanja .env already present — keeping it"
else
  SKB=$(openssl rand -base64 48)
  # Hex is URL-safe — it is embedded into DATABASE_URL verbatim.
  PGPW=$(openssl rand -hex 24)
  cat > /opt/maribelanja/.env <<ENV
SECRET_KEY_BASE=$SKB
POSTGRES_PASSWORD=$PGPW
PHX_HOST=maribelanja.darmawan.be
POOL_SIZE=10
SMTP_HOST=mailpit
SMTP_PORT=1025
SMTP_SSL=false
SMTP_USERNAME=
SMTP_PASSWORD=
MAIL_FROM=staging@maribelanja.local
ENV
  chmod 600 /opt/maribelanja/.env
  echo "maribelanja .env written (SECRET_KEY_BASE + POSTGRES_PASSWORD generated)"
fi

# --- caddy basic auth (protects naikbusaja /dev/* on the public internet) ----
mkdir -p /opt/caddy
if [ -f /opt/caddy/.dev-bcrypt ]; then
  echo "caddy basic auth already generated — credentials in /opt/caddy/dev-auth-credentials.txt"
else
  PW=$(openssl rand -hex 12)
  docker run --rm caddy:2-alpine caddy hash-password --plaintext "$PW" > /opt/caddy/.dev-bcrypt
  printf 'naikbusaja /dev/* basic auth (set in /opt/caddy/Caddyfile)\nuser: naikbusaja\npassword: %s\n' "$PW" \
    > /opt/caddy/dev-auth-credentials.txt
  chmod 600 /opt/caddy/.dev-bcrypt /opt/caddy/dev-auth-credentials.txt
  echo "caddy basic auth generated — user: naikbusaja  password: $PW"
  echo "(also saved to /opt/caddy/dev-auth-credentials.txt on the server)"
fi

echo "== secrets ready =="
