@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'capturing_inappwebview_platform.dart';
import 'email_content_pipeline.dart';
import 'fixture_emails.dart';
import 'inline_images.dart';
import 'render_target.dart';

/// Documents of a few emails for the one-off device calibration (see
/// playwright/calibrate.sh): written for the browser harness and as a Dart file
/// the device test loads. Skipped unless HTML_RENDER_CALIBRATION_DIR is set.
const _emails = {'eml_1', 'eml_13', 'eml_17', 'eml_21', 'eml_31', 'eml_33'};
const _documentsFile = 'integration_test/tests/html_render_calibration/calibration_documents.dart';
const _metricsFile = 'test/html_render_golden/playwright/calibration/metrics.js';

final _calibrationDir = Platform.environment['HTML_RENDER_CALIBRATION_DIR'];

String _base64(String text) => base64.encode(utf8.encode(text));

void main() {
  setUp(CapturingInAppWebViewPlatform.install);

  testWidgets(
    'exports calibration documents',
    (tester) async {
      final pipeline = EmailContentPipeline();
      final cases = <Map<String, Object>>[];
      final documents = <String, String>{};
      for (final email in loadFixtureEmails().where((e) => _emails.contains(e.name))) {
        for (final target in RenderTarget.values.where((t) => t != RenderTarget.web)) {
          final content = (await tester.runAsync(() => pipeline.transform(
            raw: email.raw,
            isPlainText: email.isPlainText,
            isWeb: false,
          )))!;
          final document = inlineImages(await target.buildDocument(tester, content));
          File('$_calibrationDir/${target.label}/${email.name}.html')
            ..createSync(recursive: true)
            ..writeAsStringSync(document);
          documents['${target.label}/${email.name}'] = _base64(document);
          cases.add({
            'name': email.name,
            'target': target.label,
            'engine': target.engine,
            'width': target.pane,
            'maxHeight': target.maxHeight,
          });
        }
      }
      File('$_calibrationDir/cases.json').writeAsStringSync(jsonEncode(cases));
      File(_documentsFile).writeAsStringSync(_documentsSource(documents));
    },
    skip: _calibrationDir == null,
  );
}

String _documentsSource(Map<String, String> documents) {
  final entries = documents.entries.map((e) => "  '${e.key}': '${e.value}',").join('\n');
  return '// Overwritten by export_calibration_documents_test.dart; calibrate.sh restores it.\n'
      "const calibrationMetricsJs = '${_base64(File(_metricsFile).readAsStringSync())}';\n"
      'const calibrationDocuments = <String, String>{\n$entries\n};\n';
}
