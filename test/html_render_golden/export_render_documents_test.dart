@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'capturing_inappwebview_platform.dart';
import 'email_content_pipeline.dart';
import 'render_target.dart';

/// Writes the viewer document of every fixture email, as the app builds it,
/// for the Playwright pixel goldens (see playwright/run.sh). Skipped unless
/// HTML_RENDER_EXPORT_DIR is set (run bash test/html_render_golden/playwright/run.sh).
const _emailCount = 37;
const _webFontPath = 'assets/packages/linagora_design_flutter/assets/fonts';

final _exportDir = Platform.environment['HTML_RENDER_EXPORT_DIR'];

void main() {
  setUp(CapturingInAppWebViewPlatform.install);

  testWidgets(
    'exports fixture emails as viewer documents',
    (tester) async {
      final out = _exportDir!;
      final emails = _fixtureEmails();
      expect(emails.length, _emailCount, reason: 'fixture set changed; update _emailCount');

      final pipeline = EmailContentPipeline();
      final cases = <Map<String, Object>>[];
      for (final file in emails) {
        final name = file.uri.pathSegments.last.split('.').first;
        final raw = utf8.decode(gzip.decode(file.readAsBytesSync()));
        for (final target in RenderTarget.values) {
          final content = (await tester.runAsync(() => pipeline.transform(
            raw: raw,
            isPlainText: file.path.endsWith('.txt.gz'),
            isWeb: target == RenderTarget.web,
          )))!;
          File('$out/${target.label}/$name.html')
            ..createSync(recursive: true)
            ..writeAsStringSync(await target.buildDocument(tester, content));
          cases.add({
            'name': name,
            'target': target.label,
            'engine': target.engine,
            'width': target.pane,
            'maxHeight': target.maxHeight,
          });
        }
      }
      await _copyWebFonts(out);
      File('$out/cases.json').writeAsStringSync(jsonEncode(cases));
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: _exportDir == null,
  );
}

List<File> _fixtureEmails() => Directory('test/html_render_golden/emails')
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.html.gz') || f.path.endsWith('.txt.gz'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// Only the web app serves the design fonts (native viewers do not load them).
Future<void> _copyWebFonts(String out) async {
  final fonts = Directory.fromUri(_packageRoot('linagora_design_flutter').resolve('assets/fonts/'));
  final target = Directory('$out/web/$_webFontPath')..createSync(recursive: true);
  final ttfFiles = fonts.listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'));
  for (final font in ttfFiles) {
    font.copySync('${target.path}/${font.uri.pathSegments.last}');
  }
}

/// `flutter test` cannot resolve package URIs at runtime, so read the
/// workspace `.dart_tool/package_config.json` found above the working dir.
Uri _packageRoot(String package) {
  for (var dir = Directory.current; dir.parent.path != dir.path; dir = dir.parent) {
    final config = File('${dir.path}/.dart_tool/package_config.json');
    if (!config.existsSync()) continue;
    final packages = jsonDecode(config.readAsStringSync())['packages'] as List;
    final entry = packages.firstWhere((p) => p['name'] == package, orElse: () => null);
    if (entry == null) fail('$package is not in ${config.path}');
    return config.uri.resolve(entry['rootUri'] as String).resolve('./');
  }
  fail('no .dart_tool/package_config.json above ${Directory.current.path}');
}
