# Phase 2 — Recover a stale token via the refresh token

## Context links

- Overview: [plan.md](plan.md)
- Depends on: [Phase 1](phase-01-prefetch-drive-access-token.md)
- Decision record: `docs/adr/0106-prefetch-and-refresh-the-drive-access-token.md`
- Cozy refresh grant — https://docs.cozy.io/en/cozy-stack/auth/#post-authaccess_token

## Overview

- **Priority:** High — Phase 1 introduces caching, which introduces staleness.
  This is the phase that makes staleness invisible.
- **Status:** Not started
- **Branch:** `feature/TF-4713-2-refresh-drive-access-token`

Use the `refresh_token` the exchange response already returns to recover a stale
cached token, falling back to a full re-exchange when refresh is unavailable or
fails.

## Key insights

- Neither `/auth/token_exchange` nor Cozy's `POST /auth/access_token` returns
  `expires_in`. There is no honest expiry to pre-empt, so recovery must be
  reactive: use the token, and react to the rejection.
- The only request that carries the Drive access token is `POST /intents`, so
  there is exactly one place to detect staleness.
- The exchange response already models `refresh_token`, `client_id` and
  `client_secret`. Phase 1 carries them into `WorkplaceToken` without using them.
- `POST /auth/access_token` is the only endpoint in the package that is
  `application/x-www-form-urlencoded` rather than JSON. Its response uses the
  same field names as the exchange, so `WorkplaceExchangeTokenResponse` parses it
  unchanged.
- Cozy may or may not rotate the refresh token. Keep the old one when the
  response omits it.
- Phase 1 put the whole token lifecycle inside the `workplace` package. Recovery
  stays there: the store owns `recover`, and the extension owns the retry.
  This phase touches no file under `lib/` and no file under `core/`.

## Requirements

### Functional

- A `401` or `403` from `POST /intents` triggers one recovery and one retry.
- Recovery refreshes when the cached token is refreshable; otherwise, or if the
  refresh itself fails, it drops the cache and runs a full exchange.
- A second failure after the retry propagates unchanged into the modal's existing
  failure funnel. No new user-visible error path.
- Network and timeout errors are not staleness and must not trigger a retry.
- Recovery shares the store's in-flight de-duplication: concurrent taps recover
  once.

### Non-functional

- No change to the modal, the handshake, or any composer code.
- No change under `lib/` or `core/`. The boundary gate from Phase 1 still holds:
  `grep -rn "DriveAccessTokenStore\|WorkplaceToken\|refreshToken" lib/` returns nothing.
- `client_id` and `client_secret` are request credentials — never logged.

## Architecture

```
_fetchIntent
  ├── store.get(uri) ──▶ token
  ├── _createIntent(token) ──▶ 200 ──▶ done
  └── 401/403
        └── store.recover(uri)
              ├── token.isRefreshable ──▶ POST /auth/access_token
              │                              └── failure ──┐
              └── not refreshable ────────────────────────▶ POST /auth/token_exchange
        └── _createIntent(newToken)   (once only)
```

## Related code files

### Create

- `workplace/lib/domain/usecase/refresh_drive_token_interactor.dart`
- `workplace/test/domain/usecase/refresh_drive_token_interactor_test.dart`

### Modify

- `workplace/lib/data/datasource/workplace_datasource.dart`
- `workplace/lib/data/datasource_impl/workplace_datasource_impl.dart`
- `workplace/lib/data/repository_impl/workplace_repository_impl.dart`
- `workplace/lib/domain/repository/workplace_repository.dart`
- `workplace/lib/domain/state/workplace_intent_state.dart`
- `workplace/lib/domain/exceptions/workplace_exceptions.dart`
- `workplace/lib/presentation/manager/drive_access_token_store.dart`
- `workplace/lib/presentation/extension/workplace_composer_attachment_extension.dart`
- `workplace/test/data/workplace_datasource_impl_test.dart`
- `workplace/test/presentation/manager/drive_access_token_store_test.dart`
- `workplace/test/presentation/extension/workplace_composer_attachment_extension_test.dart`

### Delete

None.

## Implementation steps

1. **Add the refresh call** to `WorkplaceDataSourceImpl`:

   ```
   POST <platformUrl>/auth/access_token
   Content-Type: application/x-www-form-urlencoded
   grant_type=refresh_token & refresh_token & client_id & client_secret
   ```

   Build the body as a `Map` with the form content-type set on `Options`. Parse
   the response with the existing `WorkplaceExchangeTokenResponse`. Carry
   `clientId` and `clientSecret` forward from the current token, and keep the old
   `refreshToken` when the response omits one.

   Path construction mirrors `exchangeToken`: strip empty segments off
   `platformUrl.pathSegments`, then append `auth` / `access_token`.

2. **Mirror through the layers** — `WorkplaceDataSource`,
   `WorkplaceRepository`, `WorkplaceRepositoryImpl`.

3. **Add `RefreshDriveTokenInteractor`**, matching
   `exchange_drive_token_interactor.dart` exactly in shape. New states in
   `workplace_intent_state.dart`: `RefreshingWorkplaceToken`,
   `RefreshWorkplaceTokenSuccess`, `RefreshWorkplaceTokenFailure`.

4. **Add `WorkplaceRefreshTokenException`** to `workplace_exceptions.dart`,
   alongside `WorkplaceExchangeTokenException`.

5. **Add `Future<WorkplaceToken> recover(Uri platformUrl)`** to the store:
   - cached token `isRefreshable` → refresh; on success replace the cache
   - not refreshable, or the refresh threw → clear and run a full exchange
   - stored in `_inFlight` the same way `get` is, so concurrent recoveries
     collapse into one

6. **Retry once in `_fetchIntent`.** Wrap the `_createIntent` call. On a
   `DioException` whose `response?.statusCode` is `401` or `403`, call
   `store.recover(platformUrl)` and retry `_createIntent` exactly once. Anything
   else rethrows immediately. The second attempt is not retried.

7. **Construct the refresh interactor in the extension**, alongside
   `_exchangeTokenInteractor`, and pass it into `DriveAccessTokenStore`.

8. **Tests** — see Success criteria.

## Todo list

- [ ] `refreshToken` on the datasource, form-urlencoded
- [ ] Mirror through repository interface and impl
- [ ] `RefreshDriveTokenInteractor` + three states
- [ ] `WorkplaceRefreshTokenException`
- [ ] `DriveAccessTokenStore.recover` with fallback to exchange
- [ ] `_fetchIntent` retries once on 401/403 only
- [ ] Extension constructs and passes the refresh interactor
- [ ] Datasource tests for the refresh call
- [ ] Interactor tests
- [ ] Store recovery tests
- [ ] Extension retry tests
- [ ] `flutter analyze` clean
- [ ] Manual stale-token check

## Success criteria

Automated:

- `workplace_datasource_impl_test.dart` covers: the `/auth/access_token` path;
  the form-urlencoded content type; every body field; response parsing;
  `client_id` / `client_secret` carried over; the old `refresh_token` retained
  when the response omits one.
- `refresh_drive_token_interactor_test.dart` covers success and failure emission.
- `drive_access_token_store_test.dart` covers: `recover` refreshing when
  refreshable; falling back to exchange when not refreshable; falling back to
  exchange when the refresh throws; concurrent recoveries collapsing to one.
- `workplace_composer_attachment_extension_test.dart` covers: a 401 on
  `/intents` triggering recovery and exactly one retry; a second 401 propagating;
  a 500 **not** triggering a retry; a connection timeout **not** triggering a
  retry.
- `flutter analyze` and `flutter test workplace/test` pass.

Manual:

- Invalidate the token server-side, or stub the store with a bad access token,
  then tap Drive. Logs show `401` → `POST /auth/access_token` → a successful
  `POST /intents`. The picker opens normally with no toast.

## Risk assessment

- **The refresh fields may be null in practice.** Nothing has ever read them.
  If the backend leaves them empty, `recover` degrades to a plain re-exchange —
  still correct, still better than the hard failure Phase 1 alone would give.
  Capture a real response during Phase 1 testing.
- **Cozy's error shape on an invalid refresh token is undocumented.** The
  fallback-to-exchange path covers any throw, so an unexpected status is handled
  by construction rather than by matching on it.
- **Retry loops.** The retry is deliberately capped at one and scoped to two
  status codes. Do not generalise it into a Dio interceptor.
- **Form-encoded odd one out.** This is the only non-JSON request in the package;
  a copy-paste from `exchangeToken` will silently send JSON and fail. The
  content-type assertion in the datasource test guards it.

## Security considerations

- `client_id`, `client_secret` and `refresh_token` are credentials. Memory only,
  never persisted, never logged.
- Cleared by the same paths as Phase 1 — logout, account switch, OIDC userinfo
  failure, feature disabled.
- The retry never re-sends the OIDC `id_token` unless the refresh path is
  unavailable, which narrows how often the id_token leaves the app.

## Next steps

- Re-evaluate whether the picker should also prefetch the intent, once real
  latency numbers from Phases 1 and 2 are in. Deferred for now: the intent
  payload is tap-time state and `force_session_id=true` suggests it is
  session-bound.
