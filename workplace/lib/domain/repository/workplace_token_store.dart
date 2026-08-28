import 'package:workplace/domain/entity/workplace_token_session.dart';

/// Drive access token lifecycle for one platform URL: cache, single-flight
/// exchange, invalidation, and 401 recovery.
abstract class WorkplaceTokenStore {
  /// Cached session for [platformUrl], or joins/starts an exchange.
  Future<WorkplaceTokenSession> obtain({
    required Uri platformUrl,
    required String oidcIdToken,
  });

  /// Fire-and-forget obtain(); no-op on null args, swallows failures.
  Future<void> prime({Uri? platformUrl, String? oidcIdToken});

  /// Drops the cached session and any in-flight exchange.
  void clear();

  /// Recovers from a 401 on [usedAccessToken]: refresh, or fall back to exchange.
  Future<WorkplaceTokenSession> recoverAfterUnauthorized({
    required String usedAccessToken,
    required Uri platformUrl,
    required String oidcIdToken,
  });
}
