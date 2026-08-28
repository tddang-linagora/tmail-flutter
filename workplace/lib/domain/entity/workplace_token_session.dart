import 'package:equatable/equatable.dart';

/// Drive access token; no expiry, Drive never returns expires_in — staleness
/// is only known reactively.
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

  /// True when the refresh grant has everything it needs.
  bool get canRefresh =>
      (refreshToken?.isNotEmpty ?? false) &&
      (clientId?.isNotEmpty ?? false) &&
      (clientSecret?.isNotEmpty ?? false);

  @override
  List<Object?> get props => [accessToken, refreshToken, clientId, clientSecret];
}
