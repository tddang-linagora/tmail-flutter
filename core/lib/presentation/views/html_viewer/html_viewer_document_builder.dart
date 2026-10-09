import 'package:core/presentation/views/html_viewer/html_content_viewer_configuration.dart';
import 'package:core/utils/html/html_interaction.dart';
import 'package:core/utils/html/html_template.dart';
import 'package:core/utils/html/html_utils.dart';
import 'package:core/utils/html/mobile_email_responsive_layout_script.dart';
import 'package:flutter/widgets.dart';

/// Sizes the web viewer iframe document is laid out with.
class HtmlWebViewerDimensions {
  final double widthContent;
  final double minHeight;
  final double minWidth;
  final double? contentPadding;

  const HtmlWebViewerDimensions({
    required this.widthContent,
    required this.minHeight,
    required this.minWidth,
    this.contentPadding,
  });
}

/// What `HtmlContentViewerOnWeb` renders: the content, how it looks and how
/// it is laid out.
class HtmlWebViewerDocumentInput {
  final HtmlContentViewerContent content;
  final HtmlContentViewerTypography typography;
  final HtmlContentViewerBehavior behavior;
  final HtmlWebViewerDimensions dimensions;

  const HtmlWebViewerDocumentInput({
    required this.content,
    required this.typography,
    required this.behavior,
    required this.dimensions,
  });
}

/// View-id bound message and listener scripts the web widget owns. They do
/// not affect layout.
class HtmlWebViewerScripts {
  final String leading;
  final String trailing;

  const HtmlWebViewerScripts({this.leading = '', this.trailing = ''});
}

/// Builds the exact HTML document each email viewer loads, so widgets and
/// render tests share one code path.
class HtmlViewerDocumentBuilder {
  const HtmlViewerDocumentBuilder._();

  /// `HtmlContentViewer` (Android / iOS email view).
  static String buildNative({
    required HtmlContentViewerConfiguration configuration,
    required bool applyMobileResponsiveLayout,
    required bool isAndroid,
  }) {
    final behavior = configuration.behavior;
    final enableQuoteToggle = behavior.has(HtmlContentViewerFeature.quoteToggle);
    final initialWidth = configuration.layout.viewport.width;
    final scripts = [
      HtmlInteraction.scriptsHandleLazyLoadingBackgroundImage,
      if (enableQuoteToggle) HtmlUtils.quoteToggleScript,
      if (initialWidth != null)
        HtmlInteraction.generateNormalizeImageScript(initialWidth),
      if (applyMobileResponsiveLayout)
        MobileEmailResponsiveLayoutScript.generate(
          contentSizeChangedEventJSChannelName:
              HtmlInteraction.contentSizeChangedEventJSChannelName,
        ),
      if (isAndroid) HtmlInteraction.scriptsHandleContentSizeChanged,
    ].join();
    return HtmlUtils.generateHtmlDocument(
      content: _content(configuration.content.html, enableQuoteToggle),
      direction: configuration.content.direction,
      javaScripts: scripts,
      styleCSS: _css(behavior),
      contentPadding: configuration.layout.contentPadding?.value,
      useDefaultFontStyle: configuration.typography.usesDefaultFontStyle,
      fontSize: configuration.typography.fontSize,
    );
  }

  /// `HtmlContentViewerOnWeb`.
  static String buildWeb(
    HtmlWebViewerDocumentInput input, {
    HtmlWebViewerScripts scripts = const HtmlWebViewerScripts(),
  }) {
    final enableQuoteToggle =
        input.behavior.has(HtmlContentViewerFeature.quoteToggle);
    final dimensions = input.dimensions;
    final javaScripts = [
      scripts.leading,
      HtmlInteraction.scriptsDisableZoom,
      HtmlInteraction.scriptsHandleLazyLoadingBackgroundImage,
      HtmlInteraction.generateNormalizeImageScript(dimensions.widthContent),
      if (enableQuoteToggle) HtmlUtils.quoteToggleScript,
      scripts.trailing,
    ].join();
    return HtmlUtils.generateHtmlDocument(
      content: _content(input.content.html, enableQuoteToggle),
      minHeight: dimensions.minHeight,
      minWidth: dimensions.minWidth,
      styleCSS: _css(input.behavior),
      javaScripts: javaScripts,
      direction: input.content.direction,
      contentPadding: dimensions.contentPadding,
      useDefaultFontStyle: input.typography.usesDefaultFontStyle,
      fontSize: input.typography.fontSize,
    );
  }

  /// `IosHtmlContentViewerWidget` (EML previewer, composer fullscreen).
  static String buildIos({
    required String content,
    required TextDirection? direction,
    required bool useDefaultFontStyle,
  }) =>
      HtmlUtils.generateHtmlDocument(
        content: content,
        direction: direction,
        javaScripts: HtmlInteraction.scriptsHandleLazyLoadingBackgroundImage,
        useDefaultFontStyle: useDefaultFontStyle,
        fontSize: 16,
      );

  static String _content(String html, bool enableQuoteToggle) =>
      enableQuoteToggle ? HtmlUtils.addQuoteToggle(html) : html;

  static String _css(HtmlContentViewerBehavior behavior) => [
        if (behavior.has(HtmlContentViewerFeature.quoteToggle))
          HtmlUtils.quoteToggleStyle,
        if (behavior.has(HtmlContentViewerFeature.disableScrolling))
          HtmlTemplate.disableScrollingStyleCSS,
      ].join();
}
