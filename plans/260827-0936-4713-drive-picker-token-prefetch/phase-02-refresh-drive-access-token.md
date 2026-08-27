# Phase 2 — Recover a stale token on 401

Diagrams for the whole flow: [plan.md § Flows](plan.md#flows)
(happy path, 401 refresh vs re-exchange, multi-composer 401).

## Overview

- **Priority:** High — Phase 1 introduces caching, which introduces staleness.
- **Status:** Not started
- **Depends on:** Phase 1
- **Touches:** `workplace/` only. No `lib/`, no `core/`.

Refresh is **only** a reaction to `POST /intents` HTTP 401. Prefetch and
`obtain` never refresh.

## Requirements

- Functional: 401 → one recover → one retry of **that** `/intents`. Recover
  prefers `POST /auth/access_token`; falls back to `token_exchange`. Two
  composers 401 on the same access token share one recover HTTP. A second 401
  after the retry surfaces. Timeouts / 500 / 403 do not retry.
- Non-functional: no interceptor; no `RefreshDriveTokenInteractor`; no
  generation / `force`; `lib/` grep gate from Phase 1 still holds.

## When refresh vs when re-exchange

Both happen inside `recoverAfterUnauthorized`, called from `_fetchIntent`
after a 401, with the access token that just failed.

```
recoverAfterUnauthorized(usedAccessToken):
  if cache has a session AND its access token != usedAccessToken
      → return cache          // sibling already recovered; zero HTTP
  if _inFlight != null
      → return _inFlight      // join the recover already started
  start one _inFlight:
      if session.canRefresh
          try POST /auth/access_token
          on throw → POST /auth/token_exchange
      else
          POST /auth/token_exchange
```

| Situation | HTTP |
|---|---|
| Warm cache, tap | `/intents` only |
| 401, `canRefresh` | one `access_token`, one retry `/intents` |
| 401, no refresh fields or grant throws | one `token_exchange`, one retry `/intents` |
| Two composers 401 on T together | one recover HTTP, two retry `/intents` |
| A recovered to T2; B 401 on T afterwards | zero recover HTTP, B retries `/intents` with T2 |
| Retry `/intents` also 401 | error surfaces; no third attempt |

Do **not** call `obtain()` from recover — that cache-hits the dead token.

## Architecture

`_fetchIntent`:

```dart
final session = await _tokenStore.obtain(...);
try {
  return await _createIntent(platformUrl, session.accessToken, ...);
} catch (e) {
  if (!_isUnauthorized(e)) rethrow;
  final fresh = await _tokenStore.recoverAfterUnauthorized(
    usedAccessToken: session.accessToken,
    platformUrl: platformUrl,
    oidcIdToken: oidcToken,
  );
  return _createIntent(platformUrl, fresh.accessToken, ...);
}

bool _isUnauthorized(Object error) =>
    error is DioException && error.response?.statusCode == 401;
```

The second `_createIntent` is not wrapped. Unwrap is already done: datasource
throws `DioException` → `CreateWorkplaceIntentFailure` → `_createIntent`
rethrows `failure.exception`.

Trigger is **HTTP 401 only**. Do not match 403 (permission, not expiry). Do
not add WWW-Authenticate / body-regex matching unless a captured Drive 401
proves the status is missing. Dio often has an empty body; the status check
is the one that actually fires.

Refresh call (no Bearer, credentials in the form body):

```
POST {platform}/auth/access_token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token&refresh_token=...&client_id=...&client_secret=...
```

Parse with existing `WorkplaceExchangeTokenResponse`. Carry client id/secret
forward. Keep the previous refresh token if the response omits one.

## Related code files

Modify:

- `workplace/lib/data/datasource/workplace_datasource.dart`
- `workplace/lib/data/datasource_impl/workplace_datasource_impl.dart`
- `workplace/lib/domain/repository/workplace_repository.dart`
- `workplace/lib/data/repository_impl/workplace_repository_impl.dart`
- `workplace/lib/domain/repository/workplace_token_store.dart` — add
  `recoverAfterUnauthorized`
- `workplace/lib/data/network/in_memory_workplace_token_store.dart`
- `workplace/lib/presentation/extension/workplace_composer_attachment_extension.dart`
- tests: datasource, store, extension

Delete:

- `workplace/lib/domain/usecase/exchange_drive_token_interactor.dart` if Phase 1
  left it unused
- unused `ExchangingWorkplaceToken` / `ExchangeWorkplaceTokenSuccess` /
  `ExchangeWorkplaceTokenFailure` after grep shows no remaining references

Keep `WorkplaceExchangeTokenException`. Do **not** add
`RefreshDriveTokenInteractor` or refresh success/failure states — the store
calls the repository.

## Implementation steps

1. Add `refreshToken(Uri platformUrl, WorkplaceTokenSession current)` on
   datasource / repository. Form body, no `Authorization`. Throw if
   `!current.canRefresh`.

2. Pass `refresh: _repository.refreshToken` into `InMemoryWorkplaceTokenStore`.

3. Implement `recoverAfterUnauthorized` with the table above. Reuse the same
   `_inFlight` slot as `obtain` — a recover never overlaps a still-running
   obtain (recover runs after `/intents` failed, which means obtain already
   completed).

4. Wire the 401 retry in `_fetchIntent`. Keep `createIntent(... accessToken:)`.

5. Delete unused exchange interactor / states.

6. Tests — see success criteria.

## Success criteria

Datasource:

- Refresh POST path ends with `auth/access_token`; body is form not JSON; no
  `Authorization`; omitted `refresh_token` in the response keeps the previous
  one; client id/secret carried over.

Store:

- `recoverAfterUnauthorized` with a newer cached access token → zero HTTP.
- Same token, `canRefresh` → one `access_token`, zero `token_exchange`.
- Same token, not `canRefresh` → one `token_exchange`.
- Refresh throws → one `token_exchange`.
- N concurrent `recoverAfterUnauthorized(T)` → one recover HTTP.

Extension:

- `/intents` 401 once, `canRefresh` → one `access_token`, one retry
  `/intents`, zero extra `token_exchange`; caller gets 200.
- `/intents` 401 twice → no third `/intents`.
- 403 / 500 / timeout → no recover, no retry.
- Two overlapping `_fetchIntent` 401s share one recover (drive this with a
  counting adapter; do not stub the store).

Manual: force a stale access token, tap Drive. Logs show `401` →
`POST /auth/access_token` → successful `POST /intents`. Picker opens, no toast.

## Risk assessment

- Refresh fields may be null in production. Recover degrades to re-exchange.
  Still better than Phase 1's hard failure.
- Retry is capped at one and scoped to 401. Do not generalise into an
  interceptor.
- Form-encoded is the only non-JSON request in the package; pin it with a
  datasource test so a copy-paste from `exchangeToken` cannot silently send
  JSON.

## Next steps

ADR 0106 from the merged code, not from this plan. Filename:
`docs/adr/0106-prefetch-and-refresh-the-drive-access-token.md`. Forward-pointer
from ADR 0095. No phase numbers in the ADR text.
