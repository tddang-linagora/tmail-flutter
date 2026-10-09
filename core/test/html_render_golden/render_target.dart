import 'package:core/presentation/constants/constants_ui.dart';
import 'package:core/presentation/views/html_viewer/html_content_viewer_configuration.dart';
import 'package:core/presentation/views/html_viewer/html_viewer_document_builder.dart';
import 'package:flutter/widgets.dart';

/// A viewer the golden test screenshots: the document the app builds for it,
/// the browser engine that approximates its webview, and the email pane width.
///
/// App width = pane + the Email View horizontal padding (native 12+12,
/// web 16+16); below 600 the app uses its mobile layout (16px text).
enum RenderTarget {
  /// `HtmlContentViewer` on Android (Chromium-based WebView).
  nativeAndroid('native-android', 'chromium', 390, 24),

  /// `HtmlContentViewer` on iOS (WKWebView).
  nativeIos('native-ios', 'webkit', 390, 24),

  /// `HtmlContentViewerOnWeb` in the browser pane.
  web('web', 'chromium', 1000, 32),

  /// `IosHtmlContentViewerWidget` (EML previewer).
  iosPreviewer('ios-previewer', 'webkit', 390, 0);

  const RenderTarget(this.label, this.engine, this.pane, this.padding);

  final String label;
  final String engine;
  final int pane;
  final int padding;

  double get appWidth => (pane + padding).toDouble();

  bool get isMobile => appWidth < 600;

  double get fontSize => isMobile ? 16 : 14;

  /// The viewer document for already transformed [content].
  String buildDocument(String content) => switch (this) {
        RenderTarget.web => HtmlViewerDocumentBuilder.buildWeb(
            _webInput(content),
          ),
        RenderTarget.iosPreviewer => HtmlViewerDocumentBuilder.buildIos(
            content: content,
            direction: null,
            useDefaultFontStyle: true,
          ),
        RenderTarget.nativeAndroid ||
        RenderTarget.nativeIos =>
          HtmlViewerDocumentBuilder.buildNative(
            configuration: _nativeConfiguration(content),
            applyMobileResponsiveLayout: true,
            isAndroid: this == RenderTarget.nativeAndroid,
          ),
      };

  HtmlContentViewerTypography get _typography => HtmlContentViewerTypography(
        fontStyle: HtmlContentViewerFontStyle.defaultStyle,
        textSize: HtmlContentViewerLength(fontSize),
      );

  HtmlContentViewerConfiguration _nativeConfiguration(String content) =>
      HtmlContentViewerConfiguration(
        content: HtmlContentViewerContent(html: content),
        layout: HtmlContentViewerLayout(
          viewport: HtmlContentViewerViewport(
            constraints: BoxConstraints.tightFor(width: appWidth),
          ),
          contentPadding: const HtmlContentViewerLength(0),
        ),
        typography: _typography,
        behavior: HtmlContentViewerBehavior(features: {
          HtmlContentViewerFeature.quoteToggle,
          HtmlContentViewerFeature.mobileResponsiveLayout,
        }),
      );

  HtmlWebViewerDocumentInput _webInput(String content) =>
      HtmlWebViewerDocumentInput(
        content: HtmlContentViewerContent(html: content),
        typography: _typography,
        behavior: HtmlContentViewerBehavior(features: {
          HtmlContentViewerFeature.quoteToggle,
        }),
        dimensions: HtmlWebViewerDimensions(
          widthContent: appWidth,
          minHeight: ConstantsUI.htmlContentMinHeight,
          minWidth: ConstantsUI.htmlContentMinWidth,
          contentPadding: 0,
        ),
      );
}
