import 'package:equatable/equatable.dart';

/// A Drive access token plus what's needed to recover it once it goes stale.
///
/// Neither `/auth/token_exchange` nor `/auth/access_token` returns
/// `expires_in`, so this carries no expiry — staleness is only known
/// reactively, from a 401 on `/intents`.
class WorkplaceTokenSession with EquatableMixin {
  final String accessToken;
  final String? refreshToken;
  final String? clientId;
  final String? clientSecret;

  const WorkplaceTokenSession({
    required this.accessToken,
    this.refreshToken,
    this.clientId,
    this.clientSecret,
  });

  /// True only when the refresh grant has everything it needs. False leaves
  /// recovery to fall back to a full re-exchange.
  bool get canRefresh =>
      (refreshToken?.isNotEmpty ?? false) &&
      (clientId?.isNotEmpty ?? false) &&
      (clientSecret?.isNotEmpty ?? false);

  @override
  List<Object?> get props => [accessToken, refreshToken, clientId, clientSecret];
}
