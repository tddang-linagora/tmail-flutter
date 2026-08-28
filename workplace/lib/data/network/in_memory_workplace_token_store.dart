import 'package:workplace/domain/entity/workplace_token_session.dart';
import 'package:workplace/domain/repository/workplace_token_store.dart';

/// Exchanges an OIDC id token for a session; injected to keep the store
/// decoupled.
typedef WorkplaceTokenExchange = Future<WorkplaceTokenSession> Function(
  Uri platformUrl,
  String oidcIdToken,
);

/// Refreshes a session's access token; injected for the same reason.
typedef WorkplaceTokenRefresh = Future<WorkplaceTokenSession> Function(
  Uri platformUrl,
  WorkplaceTokenSession current,
);

/// RAM-only store, one session + one in-flight exchange. Stub — logic lands
/// in a follow-up.
class InMemoryWorkplaceTokenStore implements WorkplaceTokenStore {
  InMemoryWorkplaceTokenStore({
    required WorkplaceTokenExchange exchange,
    required WorkplaceTokenRefresh refresh,
  })  : _exchange = exchange,
        _refresh = refresh;

  final WorkplaceTokenExchange _exchange;
  final WorkplaceTokenRefresh _refresh;

  @override
  Future<WorkplaceTokenSession> obtain({
    required Uri platformUrl,
    required String oidcIdToken,
  }) {
    // TODO: cache hit, join in-flight, or exchange.
    throw UnimplementedError();
  }

  @override
  Future<void> prime({Uri? platformUrl, String? oidcIdToken}) {
    // TODO: no-op on null args, fire-and-forget obtain(), swallow failures.
    throw UnimplementedError();
  }

  @override
  void clear() {
    // TODO: drop the cached session and any in-flight exchange.
    throw UnimplementedError();
  }

  @override
  Future<WorkplaceTokenSession> recoverAfterUnauthorized({
    required String usedAccessToken,
    required Uri platformUrl,
    required String oidcIdToken,
  }) {
    // TODO: cache-coherence check, join in-flight, refresh, or fall back to exchange.
    throw UnimplementedError();
  }
}
