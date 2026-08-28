import 'package:workplace/domain/entity/workplace_token_session.dart';

/// Owns the Drive access token's lifecycle for one platform URL: caching,
/// single-flight exchange, and invalidation.
///
/// `recoverAfterUnauthorized` is deliberately not on this port yet — Phase 2
/// adds it once the refresh grant exists. Do not ship a method that lies.
///
/// See `plans/260827-0936-4713-drive-picker-token-prefetch/phase-01-prefetch-drive-access-token.md`
/// § "Store port" for the full contract this will implement.
abstract class WorkplaceTokenStore {
  /// Returns the cached session for [platformUrl] when one exists, joins an
  /// exchange already in flight for it, or starts a new one.
  ///
  /// A different [platformUrl] than the one currently cached discards the
  /// cache before proceeding.
  Future<WorkplaceTokenSession> obtain({
    required Uri platformUrl,
    required String oidcIdToken,
  });

  /// Fire-and-forget [obtain]. No-op when [platformUrl] or [oidcIdToken] is
  /// null. Swallows and logs any failure — never throws.
  Future<void> prime({Uri? platformUrl, String? oidcIdToken});

  /// Drops the cached session and any in-flight exchange.
  void clear();
}
