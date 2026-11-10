# Google OAuth on staging (naikbusaja)

Date: 2026-11-09
Status: deployed 2026-11-09 — authorize redirect carries the real client_id, Google serves the sign-in page

## Problem

Google sign-in on naikbusaja staging failed with
`authError=invalid_client — The OAuth client was not found`, and the failing
request carried `client_id=dummy_google_client_id`. Adding `GOOGLE_CLIENT_ID` /
`GOOGLE_CLIENT_SECRET` to `/opt/naikbusaja/.env` and re-running `make naikbusaja`
changed nothing, because two independent gaps made the values unreachable:

1. **Compose never passed them.** `staging/apps/naikbusaja/docker-compose.staging.yml`
   had no `GOOGLE_*` entries in the app's `environment:` block — compose only
   forwards what is listed, so the container had no `GOOGLE_*` at all
   (`docker exec naikbusaja-app env | grep -i google` → empty, while the
   server `.env` had both keys).
2. **The value was baked at build time.** naikbusaja read the credentials in
   `config/config.exs` (compile-time), which runs during `mix release` inside
   the image build where no `GOOGLE_*` exists. The placeholder was frozen into
   `/app/releases/0.1.0/sys.config` as byte literals
   (`<<100,117,109,109,121,...>>` = `"dummy_google_client_id"`), so the runtime
   container env could not have overridden it even if it had been set.

## What changed

- `naikbusaja/config/runtime.exs` (repo `~/projects/naikbusaja`): reads
  `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` at boot and configures
  `Ueberauth.Strategy.Google.OAuth` only when both are non-empty. Verified the
  dependency reads config at call time
  (`Application.get_env` in `Ueberauth.Strategy.Google.OAuth.client/1`), so
  runtime config wins over the compiled placeholder.
- `staging/apps/naikbusaja/docker-compose.staging.yml`: the app `environment:`
  block gains `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` (defaults empty,
  matching maribelanja's compose).
- `staging/apps/naikbusaja/.env.example`: documents both vars and the exact
  redirect URI that must be registered on the OAuth client.

The compile-time block in `config/config.exs` is untouched — it still supplies
the dummy fallback, which keeps dev and test working without credentials.

## Verification

- `docker exec naikbusaja-app env | grep -i google` → both vars present.
- `Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth)` inside the
  release → the real client id/secret, not the placeholders.
- `GET https://naikbusaja.darmawan.be/auth/google` →
  `302 …client_id=508859143249-…apps.googleusercontent.com&redirect_uri=https%3A%2F%2Fnaikbusaja.darmawan.be%2Fauth%2Fgoogle%2Fcallback&scope=email+profile`
- Following that redirect returns HTTP 200 with `<title>Sign in - Google Accounts</title>`
  — no `invalid_client` / `redirect_uri_mismatch` in the page. Both the client
  id and the registered redirect URI are accepted.
- All three containers healthy; no errors or warnings in `naikbusaja-app` logs;
  site root still redirects to `/users/login` as before.

## Notes

- Runtime-not-compile-time is the general lesson here: `config.exs` is
  evaluated during `mix release`, so any `System.get_env` there is captured at
  image build, not at boot. Values that live in the server's `.env` must be
  read from `runtime.exs`.
- maribelanja was already correct on both counts (`runtime.exs` + `x-app-env`),
  which is why its Google sign-in worked while naikbusaja's did not.
- The `GOOGLE_CLIENT_SECRET` was never echoed into chat, git, or this repo;
  only its shape (`GOCSPX-` prefix, 35 chars) was inspected during diagnosis.
