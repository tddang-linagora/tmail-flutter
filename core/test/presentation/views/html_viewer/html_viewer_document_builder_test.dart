import 'package:core/presentation/views/html_viewer/html_content_viewer_configuration.dart';
import 'package:core/presentation/views/html_viewer/html_viewer_document_builder.dart';
import 'package:core/utils/html/html_interaction.dart';
import 'package:core/utils/html/html_template.dart';
import 'package:core/utils/html/html_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

HtmlContentViewerConfiguration _nativeConfiguration(
  Set<HtmlContentViewerFeature> features,
) =>
    HtmlContentViewerConfiguration(
      content: const HtmlContentViewerContent(html: '<p>hello</p>'),
      layout: const HtmlContentViewerLayout(
        viewport: HtmlContentViewerViewport(
          constraints: BoxConstraints.tightFor(width: 414),
        ),
        contentPadding: HtmlContentViewerLength(0),
      ),
      typography: const HtmlContentViewerTypography(
        fontStyle: HtmlContentViewerFontStyle.defaultStyle,
        textSize: HtmlContentViewerLength(16),
      ),
      behavior: HtmlContentViewerBehavior(features: features),
    );

HtmlWebViewerDocumentInput _webInput(Set<HtmlContentViewerFeature> features) =>
    HtmlWebViewerDocumentInput(
      content: const HtmlContentViewerContent(html: '<p>hello</p>'),
      typography: const HtmlContentViewerTypography(
        fontStyle: HtmlContentViewerFontStyle.defaultStyle,
        textSize: HtmlContentViewerLength(14),
      ),
      behavior: HtmlContentViewerBehavior(features: features),
      dimensions: const HtmlWebViewerDimensions(
        widthContent: 1032,
        minHeight: 150,
        minWidth: 300,
        contentPadding: 0,
      ),
    );

void main() {
  group('HtmlViewerDocumentBuilder', () {
    test('buildNative SHOULD add the quote toggle style and script when enabled', () {
      final document = HtmlViewerDocumentBuilder.buildNative(
        configuration: _nativeConfiguration({HtmlContentViewerFeature.quoteToggle}),
        applyMobileResponsiveLayout: false,
        isAndroid: false,
      );

      expect(document, contains(HtmlUtils.quoteToggleStyle));
      expect(document, contains(HtmlUtils.quoteToggleScript));
      expect(document, contains(HtmlInteraction.generateNormalizeImageScript(414)));
    });

    test('buildNative SHOULD only add the Android size script on Android', () {
      final configuration = _nativeConfiguration({});

      final android = HtmlViewerDocumentBuilder.buildNative(
        configuration: configuration,
        applyMobileResponsiveLayout: false,
        isAndroid: true,
      );
      final ios = HtmlViewerDocumentBuilder.buildNative(
        configuration: configuration,
        applyMobileResponsiveLayout: false,
        isAndroid: false,
      );

      expect(android, contains(HtmlInteraction.scriptsHandleContentSizeChanged));
      expect(ios, isNot(contains(HtmlInteraction.scriptsHandleContentSizeChanged)));
    });

    test('buildNative SHOULD disable scrolling when the feature is set', () {
      final document = HtmlViewerDocumentBuilder.buildNative(
        configuration: _nativeConfiguration({HtmlContentViewerFeature.disableScrolling}),
        applyMobileResponsiveLayout: false,
        isAndroid: false,
      );

      expect(document, contains(HtmlTemplate.disableScrollingStyleCSS));
      expect(document, isNot(contains(HtmlUtils.quoteToggleStyle)));
    });

    test('buildWeb SHOULD keep leading scripts before and trailing scripts after the built-ins', () {
      final document = HtmlViewerDocumentBuilder.buildWeb(
        _webInput({HtmlContentViewerFeature.quoteToggle}),
        scripts: const HtmlWebViewerScripts(
          leading: '/*leading*/',
          trailing: '/*trailing*/',
        ),
      );

      final leading = document.indexOf('/*leading*/');
      final zoom = document.indexOf(HtmlInteraction.scriptsDisableZoom);
      final normalize = document.indexOf(HtmlInteraction.generateNormalizeImageScript(1032));
      final quote = document.indexOf(HtmlUtils.quoteToggleScript);
      final trailing = document.indexOf('/*trailing*/');

      expect(leading, greaterThanOrEqualTo(0));
      expect(leading, lessThan(zoom));
      expect(zoom, lessThan(normalize));
      expect(normalize, lessThan(quote));
      expect(quote, lessThan(trailing));
    });

    test('buildIos SHOULD load only the lazy background image script', () {
      final document = HtmlViewerDocumentBuilder.buildIos(
        content: '<p>hello</p>',
        direction: TextDirection.rtl,
        useDefaultFontStyle: true,
      );

      expect(document, contains(HtmlInteraction.scriptsHandleLazyLoadingBackgroundImage));
      expect(document, isNot(contains(HtmlUtils.quoteToggleScript)));
      expect(document, contains('<p>hello</p>'));
    });
  });
}
