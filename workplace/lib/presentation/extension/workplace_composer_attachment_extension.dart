import 'package:core/presentation/extensions/composer_attachment_plugin.dart';
import 'package:core/presentation/extensions/composer_toolbar_button_style.dart';
import 'package:core/presentation/resources/image_paths.dart';
import 'package:core/presentation/state/failure.dart';
import 'package:core/utils/app_logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:workplace/data/datasource_impl/workplace_datasource_impl.dart';
import 'package:workplace/data/model/workplace_enums.dart';
import 'package:workplace/data/model/workplace_intent_request.dart';
import 'package:workplace/data/network/in_memory_workplace_token_store.dart';
import 'package:workplace/data/repository_impl/workplace_repository_impl.dart';
import 'package:workplace/domain/entity/workplace_action_config.dart';
import 'package:workplace/domain/entity/workplace_intent.dart';
import 'package:workplace/domain/entity/workplace_theme.dart';
import 'package:workplace/domain/exceptions/workplace_exceptions.dart';
import 'package:workplace/domain/repository/workplace_token_store.dart';
import 'package:workplace/presentation/model/drive_pick_state.dart';
import 'package:workplace/presentation/model/drive_picker_session.dart';
import 'package:workplace/domain/state/workplace_intent_state.dart';
import 'package:workplace/domain/usecase/create_drive_intent_interactor.dart';
import 'package:workplace/presentation/widget/drive_attachment_context_menu_tile.dart';
import 'package:workplace/presentation/widget/drive_attachment_picker_button.dart';

typedef OnDrivePickStateChanged =
    Future<void> Function(String? composerId, DrivePickState state);

/// The composer-side inputs the extension reads at picker-open time — bundled
/// so the constructor stays under the 5-arg limit.
typedef WorkplaceAttachmentGetters = ({
  ValueGetter<bool> uploadFromUrlSupported,
  String? Function() oidcTokenGetter,
  num? Function() maxAttachmentSizeBytesGetter,
  num? Function(String? composerId) remainingAttachmentCapacityBytesGetter,
});

class WorkplaceComposerAttachmentExtension implements ComposerAttachmentPlugin {
  final ValueListenable<Uri?> workplaceUri;
  final WorkplaceAttachmentGetters getters;
  final OnDrivePickStateChanged? onPickState;

  late final _dataSource = WorkplaceDataSourceImpl();
  late final _repository = WorkplaceRepositoryImpl(_dataSource);
  late final _createIntentInteractor = CreateDriveIntentInteractor(_repository);

  late final WorkplaceTokenStore _tokenStore = InMemoryWorkplaceTokenStore(
    exchange: (platformUrl, oidcIdToken) => throw UnimplementedError(),
    refresh: _repository.refreshToken,
  );

  WorkplaceComposerAttachmentExtension({
    required this.workplaceUri,
    required this.getters,
    this.onPickState,
  }) {
    _watchUri();
  }

  void _watchUri() {
    workplaceUri.addListener(_onUriChanged);
    _onUriChanged();
  }

  void _onUriChanged() {
    final uri = workplaceUri.value;
    if (uri == null) {
      _tokenStore.clear();
    } else {
      _tokenStore.prime(platformUrl: uri, oidcIdToken: getters.oidcTokenGetter());
    }
  }

  @override
  void dispose() {
    workplaceUri.removeListener(_onUriChanged);
    _tokenStore.clear();
  }

  Future<WorkplaceIntent> _fetchIntent(
    Uri platformUrl, {
    required WorkplaceFilePickerConfigRequest filePickerConfig,
  }) async {
    final oidcToken = getters.oidcTokenGetter();
    if (oidcToken == null) throw StateError('OIDC token is unavailable');
    final session = await _tokenStore.obtain(
      platformUrl: platformUrl,
      oidcIdToken: oidcToken,
    );
    try {
      return await _createIntent(
        platformUrl,
        session.accessToken,
        filePickerConfig: filePickerConfig,
      );
    } catch (e) {
      if (!_isUnauthorized(e)) rethrow;
      // A recover failure propagates like any other _fetchIntent failure — no extra catch.
      final fresh = await _tokenStore.recoverAfterUnauthorized(
        usedAccessToken: session.accessToken,
        platformUrl: platformUrl,
        oidcIdToken: oidcToken,
      );
      return _createIntent(
        platformUrl,
        fresh.accessToken,
        filePickerConfig: filePickerConfig,
      );
    }
  }

  bool _isUnauthorized(Object error) =>
      error is DioException && error.response?.statusCode == 401;

  Future<WorkplaceIntent> _createIntent(
    Uri platformUrl,
    String accessToken, {
    required WorkplaceFilePickerConfigRequest filePickerConfig,
  }) async {
    WorkplaceIntent? intent;
    await for (final either in _createIntentInteractor.execute(
      platformUrl,
      accessToken,
      addAsLink: WorkplaceActionConfig(label: filePickerConfig.sharingLink.label),
      addAsAttachment: filePickerConfig.downloadLink == null
          ? null
          : WorkplaceActionConfig(
              label: filePickerConfig.downloadLink!.label,
              maxFileSize: filePickerConfig.downloadLink!.maxFileSize,
              availableSize: filePickerConfig.downloadLink!.availableSize,
            ),
      theme: switch (filePickerConfig.theme.type) {
        WorkplaceThemeType.light => WorkplaceTheme.light,
        WorkplaceThemeType.dark => WorkplaceTheme.dark,
      },
    )) {
      either.fold(
        (failure) {
          logWarning(
            'WorkplaceComposerAttachmentExtension::_createIntent failed: $failure',
          );
          throw failure is FeatureFailure ? failure.exception : WorkplaceCreateIntentException();
        },
        (success) {
          if (success is CreateWorkplaceIntentSuccess) intent = success.intent;
        },
      );
    }
    return intent!;
  }

  @override
  Widget buildToolbarButton(
    BuildContext context, {
    required String composerId,
    required ImagePaths imagePaths,
    ComposerToolbarButtonStyle style = const ComposerToolbarButtonStyle(),
  }) {
    return ValueListenableBuilder<Uri?>(
      valueListenable: workplaceUri,
      builder: (_, uri, __) {
        if (uri == null) return const SizedBox.shrink();
        return DriveAttachmentPickerButton(
          composerId: composerId,
          imagePaths: imagePaths,
          style: style,
          session: _sessionFor(uri, composerId),
          onPickCallback: onPickState == null
              ? null
              : (state) => onPickState!(composerId, state),
        );
      },
    );
  }

  @override
  Widget buildContextMenuTile(
    BuildContext context, {
    required ImagePaths imagePaths,
  }) {
    return ValueListenableBuilder<Uri?>(
      valueListenable: workplaceUri,
      builder: (_, uri, __) {
        if (uri == null) return const SizedBox.shrink();
        return DriveAttachmentContextMenuTile(
          imagePaths: imagePaths,
          session: _sessionFor(uri, null),
          onPickCallback: onPickState == null
              ? null
              : (state) => onPickState!(null, state),
        );
      },
    );
  }

  DrivePickerSession _sessionFor(Uri uri, String? composerId) => DrivePickerSession(
        uploadFromUrlSupported: getters.uploadFromUrlSupported,
        maxAttachmentSizeBytesGetter: getters.maxAttachmentSizeBytesGetter,
        remainingAttachmentCapacityBytesGetter: () =>
            getters.remainingAttachmentCapacityBytesGetter(composerId),
        onFetchIntent: ({required filePickerConfig}) => _fetchIntent(
          uri,
          filePickerConfig: filePickerConfig,
        ),
      );
}
