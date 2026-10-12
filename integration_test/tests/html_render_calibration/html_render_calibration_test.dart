import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The webview package is reached through `core`, which owns the dependency.
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:patrol/patrol.dart';

import 'calibration_documents.dart';

/// One-off comparison of the golden harness with the device webview (see
/// test/html_render_golden/playwright/calibrate.sh). Needs no backend and is
/// skipped unless the script passes --dart-define=HTML_RENDER_CALIBRATION=true.
const _enabled = bool.fromEnvironment('HTML_RENDER_CALIBRATION');
const _maxWaits = 80;

void main() {
  patrolTest(
    'html render calibration metrics',
    skip: !_enabled,
    ($) async {
      final target = Platform.isIOS ? 'native-ios' : 'native-android';
      final ids = calibrationDocuments.keys.where(
        (id) => id.startsWith('$target/') || (Platform.isIOS && id.startsWith('ios-previewer/')),
      );
      for (final id in ids) {
        final document = utf8.decode(base64.decode(calibrationDocuments[id]!));
        // HtmlContentViewer disables zoom; IosHtmlContentViewerWidget keeps the default.
        final metrics = await _documentMetrics($, document, supportZoom: !id.startsWith('native-'));
        debugPrint('CALIBRATION_JSON ${jsonEncode({'case': id, 'metrics': metrics})}');
      }
    },
  );
}

/// Loads [document] in a bare webview with the viewer's settings and measures it.
Future<Map<String, dynamic>> _documentMetrics(
  PatrolIntegrationTester $,
  String document, {
  required bool supportZoom,
}) async {
  InAppWebViewController? controller;
  await $.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 390,
          height: 800,
          child: InAppWebView(
            key: UniqueKey(),
            initialSettings: InAppWebViewSettings(
              transparentBackground: true,
              supportZoom: supportZoom,
              verticalScrollBarEnabled: false,
            ),
            onWebViewCreated: (c) {
              controller = c;
              c.loadData(data: document);
            },
          ),
        ),
      ),
    ),
  );
  if (!await _waitUntilLoaded($, () => controller)) return {'error': 'timeout'};
  await $.tester.pump(const Duration(seconds: 2));
  final metricsJs = utf8.decode(base64.decode(calibrationMetricsJs));
  final result = await controller!.evaluateJavascript(source: '($metricsJs)()');
  return jsonDecode(result as String) as Map<String, dynamic>;
}

Future<bool> _waitUntilLoaded(PatrolIntegrationTester $, InAppWebViewController? Function() controller) async {
  for (var i = 0; i < _maxWaits; i++) {
    await $.tester.pump(const Duration(milliseconds: 250));
    final state = await controller()?.evaluateJavascript(source: 'document.readyState');
    if (state == 'complete') return true;
  }
  return false;
}
