import 'dart:convert';

import 'package:core/data/network/dio_client.dart';
import 'package:core/presentation/utils/html_transformer/html_transform.dart';
import 'package:core/presentation/utils/html_transformer/transform_configuration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model/email/email_content.dart';
import 'package:model/email/email_content_type.dart';
import 'package:model/extensions/list_email_content_extension.dart';
import 'package:tmail_ui_user/features/email/data/local/html_analyzer.dart';
import 'package:tmail_ui_user/features/upload/data/network/file_uploader.dart';
import 'package:uuid/uuid.dart';

/// The pipeline never downloads: fixtures have no CID map.
class _OfflineDioClient extends Fake implements DioClient {}

/// Only the draft-signature path uploads; the email view never does.
class _NoUploader extends Fake implements FileUploader {}

/// `HtmlAnalyzer.transformEmailContent` + `asHtmlString`, as the email view
/// runs them (web uses its own transform configuration).
class EmailContentPipeline {
  final _analyzer = HtmlAnalyzer(
    HtmlTransform(_OfflineDioClient(), const HtmlEscape()),
    _NoUploader(),
    const Uuid(),
  );

  Future<String> transform({
    required String raw,
    required bool isPlainText,
    required bool isWeb,
  }) async {
    final content = EmailContent(
      isPlainText ? EmailContentType.textPlain : EmailContentType.textHtml,
      raw,
    );
    final transformed = await _analyzer.transformEmailContent(
      content,
      const {},
      isWeb
          ? TransformConfiguration.forPreviewEmailOnWeb()
          : TransformConfiguration.forPreviewEmail(),
    );
    return [transformed].asHtmlString;
  }
}
