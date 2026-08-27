# TF-4713 — Speed up the Workplace Drive picker modal

## Problem

Every tap on the Drive button pays for two sequential round-trips before the
picker can render:

1. `POST <platformUrl>/auth/token_exchange` — OIDC `id_token` → Drive access token
2. `POST <platformUrl>/intents` — create the PICK intent

The skeleton loader is on screen for both. Step 1 depends on nothing the tap
produces, and nothing caches its result, so it is repeated on every tap.

## Goal

- Run the token exchange as early as possible — as soon as the Drive platform
  URI is available, which is effectively "as soon as the session is available".
- Reuse the `refresh_token` the exchange already returns and currently discards.
- Keep the change modular: it is temporary scaffolding, removal must stay a
  delete.

## Phases

| # | Phase | Branch | Status |
|---|-------|--------|--------|
| 0 | Plan + ADR | `feature/TF-4713-ADR-drive-token` | In progress |
| 1 | [Prefetch the Drive access token](phase-01-prefetch-drive-access-token.md) | `feature/TF-4713-1-prefetch-drive-access-token` | Not started |
| 2 | [Recover a stale token via refresh](phase-02-refresh-drive-access-token.md) | `feature/TF-4713-2-refresh-drive-access-token` | Not started |

Each phase ships value on its own. Phase 2 needs Phase 1's `WorkplaceToken` and
`DriveAccessTokenStore`, but touches them in two places only — rebasing is
mechanical.

## Ownership

The whole token lifecycle lives inside the `workplace` package.

- `DriveAccessTokenStore` is a private field of
  `WorkplaceComposerAttachmentExtension`, beside the datasource, repository and
  interactors it already owns.
- The store subscribes to the `ValueListenable<Uri?>` the extension is already
  handed, and drives its own prefetch, invalidation and teardown from it.
- `lib` names no token, no store and no refresh. Its coupling to the feature
  stays the two inputs it already supplies — `workplaceUri` and
  `oidcTokenGetter` — plus the registry it already builds.
- Phase 1 asserts this with a grep gate over `lib/`.

Phase 1 makes two small structural additions to support that:

- `ComposerAttachmentPlugin` gains a concrete no-op `dispose()`, and the
  registry fans it out, so a rebuilt registry releases the orphaned extension's
  listener and cached token.
- `DriveAttachmentEcosystemHandler.onEcosystemLoaded` reads the registry
  provider so the extension is constructed at session load rather than at first
  composer open. A registry-lifecycle statement, not a token one.

## Decisions

Recorded in `docs/adr/0106-prefetch-and-refresh-the-drive-access-token.md`.

- Staleness is reactive (401/403 → recover → retry once). Neither endpoint
  returns `expires_in`, so there is nothing honest to expire against.
- Refresh uses Cozy's `POST /auth/access_token` `refresh_token` grant.
- The intent is **not** prefetched — its payload is tap-time state and
  `force_session_id=true` suggests it is session-bound.
- The token lives in memory only. Nothing is persisted.

## Key dependencies

- `driveAttachmentUriValueProvider` — the existing composite `ValueNotifier<Uri?>`
  tracking `workplaceFqdn` + ecosystem capability + user preference. It is the
  natural "drive is usable now" signal, and the store's only trigger.
- `DriveAttachmentEcosystemHandler` — already an `appProviderContainer` call site
  on the session fan-out path; used to make the registry live early.
- ADR-0092 freezes new `appProviderContainer` call sites. Phase 1 adds one, in a
  file that already has two, and it disappears with the feature.

## Reference

- ADR-0095 — external drive file picker integration
- ADR-0096 / 0097 — postMessage handshake and intent rendering
- ADR-0105 — attach drive file via JMAP-mediated upload
- Cozy refresh grant — https://docs.cozy.io/en/cozy-stack/auth/#post-authaccess_token

## Open question

`/auth/token_exchange` is modelled with `refresh_token`, `client_id` and
`client_secret`, but nothing has ever read them. Capture one real response before
starting Phase 2 — if the backend leaves them null, the refresh path degrades to
a plain re-exchange (still correct, still better than today's hard failure).
