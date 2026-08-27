# Phase 1 — Prefetch, store, obtain

Diagrams for the whole flow: [plan.md § Flows](plan.md#flows).

## Overview

- **Priority:** High
- **Status:** Not started
- **Depends on:** nothing

Introduce `WorkplaceTokenSession` and abstract `WorkplaceTokenStore`, implement
`InMemoryWorkplaceTokenStore` (RAM + one in-flight Future), prefetch when the
Drive URI becomes available, and consume the cache from `_fetchIntent`.

No refresh and no 401 retry in this phase.

## Requirements

- Functional: URI non-null prefetches once; tap `obtain()` is a cache hit or
  joins the in-flight prefetch; two concurrent `obtain()` on an empty store
  issue one exchange; URI null clears; failed prefetch is silent and the next
  `obtain()` retries; native and web both prefetch at session load, not at
  first tap.
- Non-functional: memory only; never log token values; no TTL / `expiresAt`;
  no generation counter / `force` / `_isRefreshing`; `lib/` names no token
  type or store.

## Architecture

Seed for a cache hit is **platform URL only**. Do not seed on OIDC `id_token`
— an OIDC refresh must not drop a live Drive token. Invalidation is URI → null
(logout, account switch, capability off, user preference off).

Single-flight is one field:

```
if (cached session for this URL) return it
if (_inFlight != null) return _inFlight
_inFlight = exchange(...).then(write cache).whenComplete(clear slot if still ours)
```

`identical(_inFlight, started)` on write / slot-clear is ownership of the
current Future, not a scheduler flag. Needed because URI can go null then
non-null while a prefetch is in flight (account switch / preference toggle).
Do not add `_ongoingSeed`, generation, or `force`.

The store does not listen to the URI. The extension does:

```
workplaceUri.addListener(_onUriChanged)
_onUriChanged:
  uri == null → store.clear()
  else        → store.prime(platformUrl: uri, oidcIdToken: oidcTokenGetter())
```

Call `_onUriChanged()` once from the constructor so a URI already non-null at
construct prefetches immediately.

Warm-up: `DriveAttachmentEcosystemHandler.onEcosystemLoaded` already runs on
session fan-out. After `setEnabled(...)` (so the composite URI is current),
`read(composerAttachmentExtensionRegistryProvider)` constructs the plugin.

Teardown: `ComposerAttachmentPlugin.dispose()` concrete no-op;
`ComposerAttachmentExtensionRegistry.dispose()` fans it out; registry provider
`ref.onDispose(registry.dispose)`. Closing a composer does **not** dispose the
plugin.

## Related code files

Create:

- `workplace/lib/domain/entity/workplace_token_session.dart`
- `workplace/lib/domain/repository/workplace_token_store.dart`
- `workplace/lib/data/network/in_memory_workplace_token_store.dart`
- `workplace/test/data/network/in_memory_workplace_token_store_test.dart`

Modify — `workplace`:

- datasource + impl, repository + impl (`exchangeToken` returns `WorkplaceTokenSession`)
- `exchange_drive_token_interactor.dart` (keep compiling this phase; delete in Phase 2)
- `workplace_composer_attachment_extension.dart`
- `workplace_datasource_impl_test.dart`
- `workplace_composer_attachment_extension_test.dart`

Modify — `core`:

- `composer_attachment_plugin.dart` — concrete `void dispose() {}`
- `composer_attachment_extension_registry.dart` — fan out `dispose()`

Modify — `lib` (~3 lines, no token types):

- `composer_attachment_extension_registry_provider.dart` — `ref.onDispose(registry.dispose)`
- `drive_attachment_ecosystem_handler.dart` — `read` the registry after `setEnabled`

Delete if present (stale generated leftovers):

- `lib/main/providers/workplace/drive_access_token_store_provider.g.dart`
- `test/main/providers/workplace/drive_access_token_store_provider_test.mocks.dart`

## Implementation steps

1. **`WorkplaceTokenSession`** — `accessToken` required; nullable
   `refreshToken`, `clientId`, `clientSecret`. `canRefresh` true only when all
   three optionals are non-empty. No `expiresAt`.

2. **Widen `exchangeToken`** to `Future<WorkplaceTokenSession>` through
   datasource, repository, and the existing interactor so analyze stays green.
   Map the four fields from `WorkplaceExchangeTokenResponse`. Do not add
   `expiresIn` to the response model.

3. **Store port + impl.** Inject HTTP:

   ```dart
   typedef WorkplaceTokenExchange = Future<WorkplaceTokenSession> Function(
     Uri platformUrl,
     String oidcIdToken,
   );

   class InMemoryWorkplaceTokenStore implements WorkplaceTokenStore {
     InMemoryWorkplaceTokenStore({required WorkplaceTokenExchange exchange});
   }
   ```

   Phase 2 adds the `refresh` callback. This phase can take it as optional, or
   add a dummy that throws — prefer adding the typedef now and passing
   `_repository.refreshToken` only in Phase 2 so Phase 1 does not invent a
   refresh method. `recoverAfterUnauthorized` can be on the port from day one
   and `throw UnimplementedError` in the impl until Phase 2, **or** omitted
   from the port until Phase 2. Omit it until Phase 2 — do not ship a lying
   method.

   So Phase 1 port is `obtain`, `prime`, `clear` only.

4. **Extension owns the store.** Assign in the constructor body (not `late`
   lazy — that would defer prefetch to first tap).

   ```dart
   late final WorkplaceTokenStore _tokenStore = InMemoryWorkplaceTokenStore(
     exchange: _repository.exchangeToken,
   );
   ```

   After field init, `addListener(_onUriChanged)` then `_onUriChanged()`.

   `_fetchIntent`:

   ```dart
   final oidcToken = oidcTokenGetter();
   if (oidcToken == null) throw StateError('OIDC token is unavailable');
   final session = await _tokenStore.obtain(
     platformUrl: platformUrl,
     oidcIdToken: oidcToken,
   );
   return _createIntent(platformUrl, session.accessToken,
       filePickerConfig: filePickerConfig);
   ```

   Delete `_exchangeAccessToken`. Keep the interactor file compiling unused, or
   stop constructing it if the store talks to the repository directly (preferred:
   stop constructing it; delete the class in Phase 2 with the unused states).

5. **Plugin `dispose` + registry fan-out + `ref.onDispose`.**

6. **Ecosystem handler** — after `setEnabled(...)`:

   ```dart
   appProviderContainer.read(composerAttachmentExtensionRegistryProvider);
   ```

   Do not `read` from `ComposerController.onInit`. Do not `read` at login
   except via this handler (it already runs on session load).

7. **Codegen:** `./setup_local prod` from repo root. Not a per-package
   `build_runner`. Never `--delete-conflicting-outputs`.

8. **Tests** — see success criteria.

## Success criteria

Store (fake exchange callback, counting):

- First `obtain` → one exchange.
- Second `obtain`, same URL → still one.
- Concurrent `obtain` on empty store → one exchange, same session.
- `prime` with null uri/oidc → zero HTTP, completes.
- `prime` exchange throws → completes, no throw; next `obtain` starts one new
  exchange.
- `clear` then `obtain` → one new exchange.
- Different `platformUrl` → new exchange, does not join the previous flight.
- Late completion after `clear` does not restore the dropped session.

Extension:

- Construct with non-null URI → one `prime` / exchange.
- URI null then set → one exchange; first `_fetchIntent` after that is
  `/intents` only.
- Warm store: `_fetchIntent` issues zero `token_exchange`.
- Existing null-OIDC / exchange-failure / intent-failure tests still hold.

App:

- Registry provider dispose disposes the registry / extension.
- Boundary gate: `grep -rn "WorkplaceTokenStore\|WorkplaceTokenSession\|InMemoryWorkplaceTokenStore" lib/`
  returns nothing.

Manual, Drive-enabled backend:

1. Log in, stay on mailbox. One `token_exchange` after ecosystem load. No
   composer open.
2. Open composer, tap Drive. Only `POST /intents`. Skeleton clears sooner.
3. Second tap, same composer: still no `token_exchange`.
4. Second composer, tap Drive: `/intents` only.
5. Toggle Drive preference off then on: cache clears, one new prefetch.

## Risk assessment

- Prefetch for users who never open the picker: one request per session,
  already gated on capability + preference via the URI. Drop the ecosystem
  `read` if it proves unwanted — constructor + URI listener still prefetch at
  first composer that watches the registry, which on web is composer open.
- Eager construct: assign the store in the constructor body; a `late` lazy
  field would erase the win.
- ADR-0092 freeze on new `appProviderContainer` sites: one added in a file
  that already has them; flag in review.
- Phase 1 alone makes a stale cached token a new failure mode. Do not ship
  far ahead of Phase 2.

## Next steps

Phase 2 adds `refreshToken` on the repository, `recoverAfterUnauthorized`,
and one `/intents` retry on 401. Capture a real `token_exchange` body while
testing this phase.
