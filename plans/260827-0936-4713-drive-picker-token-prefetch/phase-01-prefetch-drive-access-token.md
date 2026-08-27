# Phase 1 — Prefetch and cache the Drive access token

## Context links

- Overview: [plan.md](plan.md)
- Decision record: `docs/adr/0106-prefetch-and-refresh-the-drive-access-token.md`
- ADR-0095 — external drive file picker integration (the flow this phase speeds up)
- ADR-0092 — Riverpod 3 upgrade (freezes new `appProviderContainer` call sites)

## Overview

- **Priority:** High — this is the bulk of the user-visible latency win.
- **Status:** Not started
- **Branch:** `feature/TF-4713-1-prefetch-drive-access-token`

Exchange the OIDC `id_token` for a Drive access token as soon as the Drive
platform URI becomes available, cache it in memory for the session, and consume
the cached value when the picker opens.

The token lifecycle lives entirely inside the `workplace` package.

## Key insights

### The flow today

- `WorkplaceComposerAttachmentExtension._fetchIntent` is the only caller of the
  token exchange. It reads the OIDC token, exchanges it, then creates the intent
  — all inside the modal's lazy `intentLoader`, i.e. after the tap.
- The exchange needs only the platform URL and the OIDC `id_token`. Both exist
  well before any composer is opened.
- `WorkplaceDataSourceImpl.exchangeToken` already parses the full
  `WorkplaceExchangeTokenResponse` and then throws away everything except
  `accessToken`.

### The ownership boundary

- The extension already receives both exchange inputs from the app tree:
  `workplaceUri` (`ValueListenable<Uri?>`) and `oidcTokenGetter`.
- It already owns its datasource, repository and interactors as private fields.
  The token store is the same kind of private detail and belongs beside them.
- `lib` therefore gains no token type, no store, no provider, no `clear()` call.
  Its only coupling to the feature stays the registry it already builds.

### Invalidation comes for free

- `driveAttachmentUriValueProvider` fuses the three signals that decide whether
  Drive is usable — fqdn from OIDC userinfo, ecosystem capability flag, user
  preference — into one `ValueNotifier<Uri?>`.
- Logout, account switch, OIDC userinfo failure and the preference toggle all
  drive it to null already.
- A store that listens to it therefore needs no new invalidation hook.

### Warm-up timing

- The registry provider is `keepAlive` but lazy. Its only consumers are
  `composer_view.dart:496` and `external_attachment_composer_button.dart:23` —
  both composer-open paths.
- One line in `DriveAttachmentEcosystemHandler.onEcosystemLoaded` reading the
  registry provider moves the warm-up to session load. That handler already runs
  on the session fan-out path (`_setUpComponentsFromSession` →
  `loadLinagoraEcosystem`).

### Teardown

- The registry provider rebuilds when `driveAttachmentUriValueProvider` changes,
  orphaning the previous extension along with its listener and cached token.
- `ComposerAttachmentPlugin` has no teardown hook today. Adding one is a
  registry-lifecycle concern, not a token concern.

## Requirements

### Functional

- A cached token is reused across taps for the lifetime of the platform URI.
- A tap arriving while a prefetch is still in flight awaits that prefetch rather
  than starting a second exchange.
- A failed prefetch is silent — no toast, no retry loop. The next `get` retries.
- A change of platform URI discards the cache.
- The URI going null clears the cache.
- Disposing the registry disposes the extension, which detaches the listener and
  drops the token.
- Behaviour with a missing OIDC token is unchanged (same `StateError`).

### Non-functional

- Memory only. Nothing persisted, nothing logged that contains a token value.
- `lib` never names a workplace token, store or refresh — no type, no provider,
  no call. `grep -rn "DriveAccessTokenStore\|WorkplaceToken" lib/` returns nothing.
- No change to the modal, the handshake, or any composer code.
- Everything removable by deleting files plus reverting one signature widening.

## Architecture

```
lib/                                  workplace/
────────────────────────────────      ──────────────────────────────────────
registry provider                     WorkplaceComposerAttachmentExtension
  builds extension ─────────────────▶   └─ owns DriveAccessTokenStore
  passes workplaceUri + oidcGetter           ├─ listens to workplaceUri
  ref.onDispose(registry.dispose) ─▶         │    non-null → prefetch()
                                             │    null     → clear()
ecosystem handler                            ├─ get() cached | in-flight | exchange
  setEnabled(...)                            └─ dispose() removeListener + clear
  read(registryProvider)   ← warm-up
```

`_fetchIntent` becomes `store.get(uri)` → `_createIntent(POST /intents)`.

## Related code files

### Delete first

Two orphaned generated files sit in the tree with no source behind them (both
gitignored, so untracked). `build_runner` and `flutter analyze` trip on them:

- `lib/main/providers/workplace/drive_access_token_store_provider.g.dart`
- `test/main/providers/workplace/drive_access_token_store_provider_test.mocks.dart`

### Create

- `workplace/lib/domain/entity/workplace_token.dart`
- `workplace/lib/presentation/manager/drive_access_token_store.dart`
- `workplace/test/presentation/manager/drive_access_token_store_test.dart`

### Modify — `core` (teardown contract)

- `core/lib/presentation/extensions/composer_attachment_plugin.dart`
- `core/lib/presentation/extensions/composer_attachment_extension_registry.dart`

### Modify — `lib` (2 files, ~3 lines)

- `lib/features/composer/presentation/providers/composer_attachment_extension_registry_provider.dart`
- `lib/features/mailbox_dashboard/presentation/linagora_ecosystem/drive_attachment_ecosystem_handler.dart`

### Modify — `workplace`

- `workplace/lib/data/datasource/workplace_datasource.dart`
- `workplace/lib/data/datasource_impl/workplace_datasource_impl.dart`
- `workplace/lib/data/repository_impl/workplace_repository_impl.dart`
- `workplace/lib/domain/repository/workplace_repository.dart`
- `workplace/lib/domain/usecase/exchange_drive_token_interactor.dart`
- `workplace/lib/domain/state/workplace_intent_state.dart`
- `workplace/lib/presentation/extension/workplace_composer_attachment_extension.dart`
- `workplace/test/data/workplace_datasource_impl_test.dart`
- `workplace/test/presentation/extension/workplace_composer_attachment_extension_test.dart`

## Implementation steps

1. **Delete the two stale generated files** listed above.

2. **Add `WorkplaceToken`.**
   Fields: `accessToken` (required), nullable `refreshToken`, `clientId`,
   `clientSecret`. Extends `Equatable`.
   Factory `WorkplaceToken.fromResponse(WorkplaceExchangeTokenResponse)` — the
   response already carries all four.
   `bool get isRefreshable` — true when refresh token, client id and client
   secret are all present. Unused this phase; it exists so Phase 2 need not
   touch this file.

3. **Widen the return type** from `String` to `WorkplaceToken` through the
   datasource interface, datasource impl, repository interface, repository impl
   and `ExchangeDriveTokenInteractor`. Rename
   `ExchangeWorkplaceTokenSuccess.accessToken` to `.token`. No logic changes.

4. **Add `DriveAccessTokenStore`.** Plain Dart — no GetX, no Riverpod, no
   `BuildContext`.

   ```dart
   DriveAccessTokenStore({
     required ValueListenable<Uri?> workplaceUri,
     required ExchangeDriveTokenInteractor exchangeInteractor,
     required String? Function() oidcTokenGetter,
   })
   ```

   Constructor body: `addListener(_onUriChanged)`, then call `_onUriChanged()`
   once — a URI already non-null at construction must prefetch immediately.

   State: `Uri? _platformUrl`, `WorkplaceToken? _token`,
   `Future<WorkplaceToken>? _inFlight`.

   - `_onUriChanged()` — non-null → `_prefetch(uri)`; null → `clear()`.
   - `_prefetch(Uri)` — fire-and-forget wrapper over `get`; catches everything
     and `logWarning`s. Never retries on its own.
   - `Future<WorkplaceToken> get(Uri platformUrl)` — if `platformUrl` differs
     from `_platformUrl`, clear first. Then: cached token → in-flight future →
     start a new exchange. The new exchange is stored in `_inFlight` before it
     is awaited, and cleared in a `finally`.
   - `void clear()` — drops all three fields.
   - `void dispose()` — `removeListener` then `clear()`.

   Move the fold-and-throw body of
   `WorkplaceComposerAttachmentExtension._exchangeAccessToken` into the store
   rather than duplicating it, including the null-OIDC-token `StateError`.

5. **Add the teardown contract in `core`.**
   `ComposerAttachmentPlugin` gains a **concrete no-op** `void dispose() {}` —
   non-breaking for existing plugins.
   `ComposerAttachmentExtensionRegistry.dispose()` fans out over `extensions`;
   drop `const` on its constructor if the analyzer requires it.

6. **The extension owns the store.** Add
   `late final DriveAccessTokenStore _tokenStore`, assigned in the **constructor
   body** — not as a lazy initialiser, since the prefetch must start at
   construction.

   `_fetchIntent` becomes:

   ```dart
   final token = await _tokenStore.get(platformUrl);
   return _createIntent(platformUrl, token.accessToken,
       filePickerConfig: filePickerConfig);
   ```

   Add `@override void dispose() => _tokenStore.dispose();`.
   Delete `_exchangeAccessToken`. Keep `_exchangeTokenInteractor` — the store
   consumes it now.

7. **Registry provider teardown.** Hold the registry in a local, call
   `ref.onDispose(registry.dispose)`, return it. No other change — no store
   construction, no new import.

8. **Ecosystem handler warm-up.** Append
   `appProviderContainer.read(composerAttachmentExtensionRegistryProvider);`
   to `onEcosystemLoaded`, **after** the existing `setEnabled(...)` call so the
   composite URI is already correct when the extension is constructed.
   `onEcosystemCleared` is untouched — the URI going null clears the store.

9. **Run codegen:** `dart run build_runner build --workspace`. Never pass
   `--delete-conflicting-outputs` in this melos workspace.

10. **Tests** — see Success criteria.

## Todo list

- [ ] Delete the two stale `drive_access_token_store_provider` generated files
- [ ] `WorkplaceToken` entity with `fromResponse` and `isRefreshable`
- [ ] Widen `exchangeToken` return type through the chain
- [ ] `ExchangeWorkplaceTokenSuccess.accessToken` → `.token`
- [ ] `DriveAccessTokenStore` — listener, prefetch / get / clear / dispose, in-flight dedupe
- [ ] `ComposerAttachmentPlugin.dispose()` + `Registry.dispose()` in `core`
- [ ] Extension constructs and disposes the store; `_exchangeAccessToken` removed
- [ ] Registry provider `ref.onDispose(registry.dispose)`
- [ ] Ecosystem handler warm-up line
- [ ] `build_runner --workspace`
- [ ] Store unit tests
- [ ] Registry provider disposal test
- [ ] Datasource test updated for `WorkplaceToken`
- [ ] Extension test: warmed store issues no exchange at tap
- [ ] `flutter analyze` clean
- [ ] Manual check on web and one mobile target

## Success criteria

Automated:

- `drive_access_token_store_test.dart` covers:
  construction with a non-null URI prefetching;
  cache hit;
  two concurrent `get`s producing exactly one exchange;
  `prefetch` swallowing a failure;
  `get` after a failed prefetch re-exchanging;
  URI → null clearing;
  a changed platform URL discarding the cache;
  `dispose()` detaching the listener.
- `workplace_composer_attachment_extension_test.dart` asserts a warmed store
  issues **no** token_exchange request at tap, that `dispose()` reaches the
  store, and that existing failure propagation is unchanged.
- `workplace_datasource_impl_test.dart` asserts `refreshToken`, `clientId` and
  `clientSecret` are parsed onto `WorkplaceToken`.
- A registry provider test asserts disposing the provider disposes the registry.
- **Boundary gate:**
  `grep -rn "DriveAccessTokenStore\|WorkplaceToken\|refreshToken" lib/`
  returns nothing.
- `flutter analyze`, `flutter test workplace/test`, and
  `flutter test test/main/providers/workplace test/features/composer` all pass.

Manual, against a Drive-enabled backend (`docs/dev/backend-setup.md`):

1. Log in, stay on the mailbox list. Logs show one `token_exchange` shortly after
   the ecosystem loads, with no composer open.
2. Open a composer, tap Drive. Only `POST /intents` is issued; the skeleton
   clears noticeably sooner than on `master`.
3. Tap again — still no second `token_exchange`.
4. Toggle the Drive preference off then on — cache clears, fresh prefetch fires.
5. Log out and back in — exactly one new `token_exchange`.

Test on web **and** one mobile target: the modal is a conditional export and the
two implementations differ.

## Risk assessment

- **Prefetching for users who never open the picker.** One extra request per
  session, already gated on the capability flag and the user preference. If it
  proves unwanted, drop the warm-up line from the ecosystem handler — the
  extension then prefetches at composer open, still ahead of the tap.
- **A cached token going stale mid-session** surfaces as the picker's existing
  generic failure. Today's behaviour never caches, so this is a new failure mode
  — it is exactly what Phase 2 fixes. Do not ship Phase 1 far ahead of Phase 2.
- **Eager store construction.** A `late final` lazy initialiser would defer the
  prefetch to the first `_fetchIntent`, silently erasing the win. Assign in the
  constructor body and cover it with the construction-time prefetch test.
- **ADR-0092 freeze** on new `appProviderContainer` call sites. One is added, in
  a file that already holds two, and it disappears with the feature. Flag it in
  review rather than working around it.
- **Signature widening** touches six files across the package. Mechanical, but it
  is the part of this phase most likely to collide with concurrent Drive work.

## Security considerations

- Token stays in memory, inside the `workplace` package. Nothing reaches Hive, so
  no ADR-0073 auto-backup exposure and no cache-migration concerns.
- Never log a token value — log presence and platform host only.
- Cleared whenever the composite URI goes null, which covers logout, account
  switch, OIDC userinfo failure, and the user disabling the feature.
- The app tree never holds a reference to the token, so no accidental widening of
  its blast radius through `lib`.
- The platform URI already enforces HTTPS outside debug builds; the store adds no
  new URL handling.

## Next steps

- Phase 2 adds the refresh-based recovery on top of the store.
- Capture one real `/auth/token_exchange` response while testing this phase, to
  confirm whether the refresh fields are populated before Phase 2 starts.
