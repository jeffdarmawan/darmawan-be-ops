# Google OAuth on staging (maribelanja)

Date: 2026-11-08
Status: executed 2026-11-08 — deployed, migration applied, Google button verified on the login page

## What changed

maribelanja gained Google sign-in (Assent), and the staging stack now wires it through.

- `staging/apps/maribelanja/docker-compose.staging.yml`: the `x-app-env` anchor passes three new vars into the app container — `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` (from the server's `.env`, defaults empty) and `GOOGLE_REDIRECT_URI` (literal `https://maribelanja.darmawan.be/auth/google/callback`, matches the route, non-secret)
- Server's `/opt/maribelanja/.env`: appended the two Google credentials, piped from the local maribelanja `.env` over SSH (secrets never pass through chat, git, or this repo)
- maribelanja migration `20261108120000_add_google_id_to_users` ran automatically via the one-shot migrate service on deploy

## Notes

- The app side treats Google as optional (`config/runtime.exs` hides the Google buttons when the vars are absent), so the compose defaults keep that behavior — empty vars render a normal login page, not a crash.
- The local maribelanja `.env` also carries a `GOOGLE_REDIRECT_URI` for dev (localhost) — deliberately not copied to the server; the compose literal overrides it either way.
- Redirect URI must be registered in Google Cloud Console on the OAuth client (done 2026-11-08).
- Deployed with `make maribelanja` (rsync + build + migrate). Verified: migrate logs show the migration, app healthy, `env` inside the container shows all three `GOOGLE_*` vars, and `https://maribelanja.darmawan.be/users/login` renders `href="/auth/google"`.
- Docs follow-up from this deploy: neither the README nor the Makefile said that `.env` changes need manual edits on the server (rsync never syncs it), and the old Makefile comment implied it got copied. Added a "`.env` never syncs" note to the README deploy section, corrected the Makefile rsync-excludes comment, and documented `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` in `staging/apps/maribelanja/.env.example`.
- Pre-existing deploy-time `mix deps.get` advisories (bandit, ecto, phoenix_html, plug_crypto) were noted in the build output — unrelated to this change, worth a dependency bump pass separately.
