import 'dart:convert';

final _placeholder = RegExp(r'https://fixture\.invalid/(?:img|cid|est)/(\d+)x(\d+)[^"\x27)\s]*');
final _remoteImg = RegExp(r'(<img\b[^>]*?\bsrc=")https?://[^"]+(")', caseSensitive: false);

String _grayImage(String width, String height) {
  final svg = '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height">'
      '<rect width="100%" height="100%" fill="#c8c8c8"/></svg>';
  return 'data:image/svg+xml;base64,${base64.encode(utf8.encode(svg))}';
}

/// Replaces image URLs by gray SVG data URIs of the same size (600x300 when unknown),
/// so a device renders offline exactly as the browser harness routes them.
String inlineImages(String html) => html
    .replaceAllMapped(_placeholder, (m) => _grayImage(m[1]!, m[2]!))
    .replaceAllMapped(_remoteImg, (m) => '${m[1]}${_grayImage('600', '300')}${m[2]}');
