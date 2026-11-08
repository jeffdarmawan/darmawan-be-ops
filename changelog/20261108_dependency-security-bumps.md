# Dependency security bumps across both staging apps

Date: 2026-11-08
Status: executed 2026-11-08 — both apps rebuilt and healthy; `mix deps.get` audits now come back clean

## What changed

Hex's audit (runs on `mix deps.get`, prints EEF advisory DB matches) flagged advisories during the Google OAuth deploy. Bumped the pinned versions in both app repos — all patch/minor bumps within the existing `mix.exs` ranges:

| Package | maribelanja | naikbusaja | Fixed in |
| --- | --- | --- | --- |
| bandit | 1.13.1 → 1.14.1 | 1.13.1 → 1.14.1 | 12 advisories (10 HIGH): HTTP/1.1 + HTTP/2 memory amplification and quadratic CPU, HPACK/flow-control limit bypasses, chunk-extension request smuggling, WebSocket frame-size bypass |
| ecto | 3.14.2 → 3.14.3 | 3.14.2 → 3.14.3 | 1 HIGH: unbounded query-cache growth from interpolated JSON paths |
| phoenix_html | 4.3.0 → 4.4.0 | 4.3.0 → 4.4.0 | 1 MEDIUM: attribute-name injection in attributes_escape/1 |
| plug_crypto | 2.2.0 → 2.2.1 | already 2.2.1 | 1 MEDIUM: secret_key_base can leak into exception messages/stack traces |

## Why bandit was the urgent one

Bandit is the HTTP server inside both Phoenix apps, reached by anonymous internet clients through Caddy. The advisories are unauthenticated remote DoS: crafted tiny frames (1-byte chunks/DATA, SETTINGS/WINDOW_UPDATE games, HPACK table tricks) amplify into unbounded memory growth or quadratic CPU on a 3.7 GB box that also runs Postgres — plus one request-smuggling vector behind the proxy.

## Deploy

- Tests before deploy: maribelanja 178 passed, naikbusaja 137 passed (deps updated locally first, both repos)
- `make maribelanja` then `make naikbusaja` (one Elixir build at a time on the 3.7 GB host)
- Post-deploy hex audit output is clean — no more "VULNERABLE!" lines in `mix deps.get`
- Verified: all containers healthy, maribelanja `/health` 200, naikbusaja `/` 302 (its auth redirect; its container healthcheck curls `/` internally)

## Notes

- mix.lock changes are **uncommitted in both app repos** (maribelanja also carries the Google OAuth work; naikbusaja was already 2 commits ahead of origin) — commit/push them whenever convenient.
- naikbusaja has no `/health` route; if we want one for parity, that's an app-side change, not infra.
