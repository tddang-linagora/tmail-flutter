import 'package:workplace/domain/entity/workplace_token_session.dart';
import 'package:workplace/domain/repository/workplace_token_store.dart';

/// Exchanges an OIDC id token for a session; injected to keep the store
/// decoupled.
typedef WorkplaceTokenExchange = Future<WorkplaceTokenSession> Function(
  Uri platformUrl,
  String oidcIdToken,
);

/// RAM-only store, one session + one in-flight exchange. Stub — logic lands
/// in a follow-up.
class InMemoryWorkplaceTokenStore implements WorkplaceTokenStore {
  InMemoryWorkplaceTokenStore({required WorkplaceTokenExchange exchange})
      : _exchange = exchange;

  final WorkplaceTokenExchange _exchange;

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
}
