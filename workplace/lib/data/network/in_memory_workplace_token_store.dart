import 'package:workplace/domain/entity/workplace_token_session.dart';
import 'package:workplace/domain/repository/workplace_token_store.dart';

/// Exchanges an OIDC id token for a [WorkplaceTokenSession]. Injected so the
/// store stays decoupled from the datasource/repository stack.
typedef WorkplaceTokenExchange = Future<WorkplaceTokenSession> Function(
  Uri platformUrl,
  String oidcIdToken,
);

/// RAM-only [WorkplaceTokenStore]: one cached session, one in-flight
/// exchange. Nothing is persisted.
///
/// Skeleton only — every method is a stub for now. The real cache-hit /
/// join-in-flight / exchange logic lands in a follow-up commit; see
/// `plans/260827-0936-4713-drive-picker-token-prefetch/phase-01-prefetch-drive-access-token.md`.
class InMemoryWorkplaceTokenStore implements WorkplaceTokenStore {
  InMemoryWorkplaceTokenStore({required WorkplaceTokenExchange exchange})
      : _exchange = exchange;

  final WorkplaceTokenExchange _exchange;

  @override
  Future<WorkplaceTokenSession> obtain({
    required Uri platformUrl,
    required String oidcIdToken,
  }) {
    // TODO(TF-4713): cache hit -> join in-flight -> exchange via _exchange.
    throw UnimplementedError();
  }

  @override
  Future<void> prime({Uri? platformUrl, String? oidcIdToken}) {
    // TODO(TF-4713): no-op on null args, fire-and-forget obtain(), swallow failures.
    throw UnimplementedError();
  }

  @override
  void clear() {
    // TODO(TF-4713): drop the cached session and any in-flight exchange.
    throw UnimplementedError();
  }
}
