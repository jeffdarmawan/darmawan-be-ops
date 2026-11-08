# NaikBusAja SMTP mailer on staging

Date: 2026-11-09
Status: deployed 2026-11-09 — magic links land in Mailpit, logins verified

## What changed

naikbusaja's `fea3bc5 feat(mailer)` (ported from maribelanja) adds an
env-gated SMTP switch (`SMTP_HOST`/`SMTP_PORT`/`SMTP_SSL`/`SMTP_USERNAME`/
`SMTP_PASSWORD`/`MAIL_FROM`). The staging compose now wires it to a bundled
Mailpit instead of leaving mail in the compiled-in `/dev/mailbox`:

- `staging/apps/naikbusaja/docker-compose.staging.yml`: app environment gains
  the six SMTP/MAIL_FROM vars (defaults point at `mailpit:1025`, blank auth,
  `MAIL_FROM` empty → app default `no-reply@naikbusaja.local`), and a `mailpit`
  service joins the stack. UI is loopback-only on host port **8026** — 8025
  belongs to maribelanja's Mailpit, and both tunnels must be able to run at
  once.
- `staging/apps/naikbusaja/.env.example`: documents the SMTP vars (all
  optional — compose defaults carry staging; a real provider only needs
  overrides in the server's `.env`). No server `.env` changes were required.
- `staging/README.md`: topology diagram, smoke tests, and gotchas updated
  (naikbusaja login flow now reads mail at localhost:8026 via SSH tunnel;
  `/dev/mailbox` still exists behind basic auth but receives nothing once
  the SMTP adapter is active).

Deployed with `make naikbusaja`; this also landed the `mix.lock` bumps the
commit carried (bandit 1.13.1 → 1.14.1 — the 10-HIGH public HTTP-server
advisories, ecto 3.14.3, phoenix_html 4.4.0), closing naikbusaja's half of
the 2026-11-08 dependency-advisory pass.

## Verification

- `docker compose ps`: app healthy, mailpit up
- Magic-link login via the site → message visible in Mailpit
  (`ssh -L 8026:127.0.0.1:8026 ubuntu@47.131.158.206` → http://localhost:8026)
