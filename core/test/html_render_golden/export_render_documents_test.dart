@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/data/network/dio_client.dart';
import 'package:core/presentation/utils/html_transformer/html_transform.dart';
import 'package:core/presentation/utils/html_transformer/transform_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_target.dart';

/// Writes the viewer document of every fixture email, as the app builds it,
/// for the Playwright pixel goldens (see run.sh). Skipped unless
/// HTML_RENDER_EXPORT_DIR is set.
const _emailCount = 37;
const _webFontPath = 'assets/packages/linagora_design_flutter/assets/fonts';

final _exportDir = Platform.environment['HTML_RENDER_EXPORT_DIR'];

/// The pipeline never downloads: fixtures have no CID map.
class _OfflineDioClient extends Fake implements DioClient {}

final _transform = HtmlTransform(_OfflineDioClient(), const HtmlEscape());

void main() {
  test(
    'exports fixture emails as viewer documents',
    () async {
      final out = _exportDir!;
      final emails = _fixtureEmails();
      expect(emails.length, _emailCount, reason: 'fixture set changed; update _emailCount');

      final cases = <Map<String, Object>>[];
      for (final file in emails) {
        final name = file.uri.pathSegments.last.split('.').first;
        final raw = file.readAsStringSync();
        for (final target in RenderTarget.values) {
          final content = await _transformed(raw, file.path.endsWith('.txt'), target);
          File('$out/${target.label}/$name.html')
            ..createSync(recursive: true)
            ..writeAsStringSync(target.buildDocument(content));
          cases.add({
            'name': name,
            'target': target.label,
            'engine': target.engine,
            'width': target.pane,
          });
        }
      }
      await _copyWebFonts(out);
      File('$out/cases.json').writeAsStringSync(jsonEncode(cases));
    },
    skip: _exportDir == null ? 'set HTML_RENDER_EXPORT_DIR to export' : false,
  );
}

List<File> _fixtureEmails() => Directory('test/html_render_golden/emails')
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.html') || f.path.endsWith('.txt'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// The email body after the app's transform pipeline for [target].
Future<String> _transformed(String raw, bool isPlainText, RenderTarget target) {
  if (isPlainText) {
    return Future.value(_transform.transformToTextPlain(
      content: raw,
      transformConfiguration: TransformConfiguration.forPlainTextEmail(),
    ));
  }
  return _transform.transformToHtml(
    htmlContent: raw,
    transformConfiguration: target == RenderTarget.web
        ? TransformConfiguration.forPreviewEmailOnWeb()
        : TransformConfiguration.forPreviewEmail(),
  );
}

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
