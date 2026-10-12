import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
// The webview package is reached through `core`, which owns the dependency.
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'calibration_documents.dart';

/// One-off comparison of the golden harness with the device webview. Run by
/// test/html_render_golden/playwright/calibrate.sh with `flutter run -t`, which
/// reads the CALIBRATION_JSON lines from stdout. Not a test: the iOS Patrol
/// target is not part of the Runner scheme, and no test binding is needed here.
const _maxWaits = 80;

void main() {
  runApp(const MaterialApp(home: _CalibrationRunner()));
}

class _CalibrationRunner extends StatefulWidget {
  const _CalibrationRunner();

  @override
  State<_CalibrationRunner> createState() => _CalibrationRunnerState();
}

class _CalibrationRunnerState extends State<_CalibrationRunner> {
  late final List<String> _ids = _selectIds();
  int _index = 0;
  InAppWebViewController? _controller;

  @override
  Widget build(BuildContext context) {
    if (_index >= _ids.length) return const SizedBox();
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 390,
        height: 800,
        child: InAppWebView(
          key: ValueKey(_index),
          initialSettings: InAppWebViewSettings(
            transparentBackground: true,
            // HtmlContentViewer disables zoom; IosHtmlContentViewerWidget keeps the default.
            supportZoom: !_ids[_index].startsWith('native-'),
            verticalScrollBarEnabled: false,
          ),
          onWebViewCreated: (controller) {
            _controller = controller;
            controller.loadData(data: _document(_ids[_index]));
            _measureCurrent();
          },
        ),
      ),
    );
  }

  List<String> _selectIds() {
    final target = Platform.isIOS ? 'native-ios' : 'native-android';
    return calibrationDocuments.keys
        .where((id) => id.startsWith('$target/') || (Platform.isIOS && id.startsWith('ios-previewer/')))
        .toList();
  }

  String _document(String id) => utf8.decode(base64.decode(calibrationDocuments[id]!));

  Future<void> _measureCurrent() async {
    final id = _ids[_index];
    final metrics = await _documentMetrics();
    // Android's logcat cuts lines at about 1000 bytes, so the size table goes on its own line.
    final sizes = metrics.remove('sizeHeights');
    debugPrint('CALIBRATION_JSON ${jsonEncode({'case': id, 'metrics': metrics})}');
    debugPrint('CALIBRATION_SIZES ${jsonEncode({'case': id, 'sizeHeights': sizes})}');
    if (_index + 1 < _ids.length) {
      setState(() => _index++);
    } else {
      debugPrint('CALIBRATION_DONE');
    }
  }

  Future<Map<String, dynamic>> _documentMetrics() async {
    final controller = _controller!;
    for (var i = 0; i < _maxWaits; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (await controller.evaluateJavascript(source: 'document.readyState') == 'complete') {
        await Future<void>.delayed(const Duration(seconds: 2));
        final metricsJs = utf8.decode(base64.decode(calibrationMetricsJs));
        final result = await controller.evaluateJavascript(source: '($metricsJs)()');
        return jsonDecode(result as String) as Map<String, dynamic>;
      }
    }
    return {'error': 'timeout'};
  }
}
