import 'dart:convert';
import 'dart:io';

/// A scrubbed real email kept as `eml_N.html.gz` / `eml_N.txt.gz`.
class FixtureEmail {
  const FixtureEmail(this.name, this.raw, {required this.isPlainText});

  final String name;
  final String raw;
  final bool isPlainText;
}

/// Fixture emails sorted by file name; run from the repository root.
List<FixtureEmail> loadFixtureEmails() {
  final files = Directory('test/html_render_golden/emails')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.html.gz') || f.path.endsWith('.txt.gz'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files)
      FixtureEmail(
        file.uri.pathSegments.last.split('.').first,
        utf8.decode(gzip.decode(file.readAsBytesSync())),
        isPlainText: file.path.endsWith('.txt.gz'),
      ),
  ];
}
