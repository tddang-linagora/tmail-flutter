import 'package:core/presentation/views/html_viewer/html_content_viewer_on_web_widget.dart';
import 'package:core/presentation/views/html_viewer/html_content_viewer_widget.dart';
import 'package:core/presentation/views/html_viewer/html_iframe_widget.dart';
import 'package:core/presentation/views/html_viewer/ios_html_content_viewer_widget.dart';
import 'package:core/utils/platform_info.dart';
import 'package:core/utils/preview_eml_file_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'capturing_inappwebview_platform.dart';

/// A viewer the golden test screenshots: the document the app builds for it,
/// the browser engine that approximates its webview, and the email pane width.
///
/// App width = pane + the Email View horizontal padding (native 12+12,
/// web 16+16); below 600 the app uses its mobile layout (16px text).
enum RenderTarget {
  /// `HtmlContentViewer` on Android (Chromium-based WebView).
  nativeAndroid('native-android', 'chromium', 390, 24, 20000),

  /// `HtmlContentViewer` on iOS (WKWebView); the app clips at 22000.
  nativeIos('native-ios', 'webkit', 390, 24, 22000),

  /// `HtmlContentViewerOnWeb` in the browser pane.
  web('web', 'chromium', 1000, 32, 20000),

  /// `IosHtmlContentViewerWidget` (EML previewer).
  iosPreviewer('ios-previewer', 'webkit', 390, 0, 20000);

  const RenderTarget(this.label, this.engine, this.pane, this.padding, this.maxHeight);

  final String label;
  final String engine;
  final int pane;
  final int padding;

  /// Tallest screenshot taken; the app itself clips longer emails.
  final int maxHeight;

  double get appWidth => (pane + padding).toDouble();

  bool get isMobile => appWidth < 600;

  double get fontSize => isMobile ? 16 : 14;

  /// The viewer document the real widget builds for already transformed [content].
  Future<String> buildDocument(WidgetTester tester, String content) => switch (this) {
        RenderTarget.web => _webDocument(tester, content),
        RenderTarget.iosPreviewer => _capture(
            tester,
            TargetPlatform.iOS,
            IosHtmlContentViewerWidget(contentHtml: _previewEml(content)),
          ),
        RenderTarget.nativeAndroid => _capture(tester, TargetPlatform.android, _nativeViewer(content)),
        RenderTarget.nativeIos => _capture(tester, TargetPlatform.iOS, _nativeViewer(content)),
      };

  Future<String> _capture(WidgetTester tester, TargetPlatform platform, Widget viewer) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await tester.pumpWidget(_host(viewer));
      await tester.pump();
      await tester.pump();
      return CapturingInAppWebViewPlatform.takeData();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// A fresh, bounded phone-sized (or pane-sized) box, as the webview platform view fills its parent.
  Widget _host(Widget viewer) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: appWidth, height: 800, child: KeyedSubtree(key: UniqueKey(), child: viewer)),
          ),
        ),
      );

  /// The iframe document of the real web viewer, read from its widget tree.
  Future<String> _webDocument(WidgetTester tester, String content) async {
    PlatformInfo.isTestingForWeb = true;
    try {
      await tester.pumpWidget(_host(HtmlContentViewerOnWeb(
        widthContent: appWidth,
        contentHtml: content,
        contentPadding: 0,
        useDefaultFontStyle: true,
        enableQuoteToggle: true,
        fontSize: fontSize,
      )));
      await tester.pump();
      await tester.pump();
      final srcdoc = tester.widget<HtmlIframeWidget>(find.byType(HtmlIframeWidget)).srcdoc;
      tester.takeException(); // HtmlElementView has no platform view registry in the VM.
      return srcdoc!;
    } finally {
      PlatformInfo.isTestingForWeb = false;
    }
  }

  /// The EML previewer wraps the body in its header document (EmailDataSourceImpl).
  static String _previewEml(String content) => PreviewEmlFileUtils().generatePreviewEml(
        appName: 'Twake Mail',
        ownEmailAddress: 'alice@example.com',
        subjectPrefix: 'Subject',
        subject: 'Render golden',
        emailContent: content,
        senderName: 'Bob',
        senderEmailAddress: 'bob@example.com',
        dateTime: 'Monday, October 12, 2026 10:00 AM',
        fromPrefix: 'From',
        toPrefix: 'To',
        ccPrefix: 'Cc',
        bccPrefix: 'Bcc',
        replyToPrefix: 'Reply-To',
        titleAttachment: 'attachment',
        attachmentIcon: '',
        toAddress: 'alice@example.com',
      );

  Widget _nativeViewer(String content) => HtmlContentViewer(
        configuration: HtmlContentViewerConfiguration(
          content: HtmlContentViewerContent(html: content),
          layout: HtmlContentViewerLayout(
            viewport: HtmlContentViewerViewport(
              constraints: BoxConstraints.tightFor(width: appWidth),
            ),
            contentPadding: const HtmlContentViewerLength(0),
          ),
          typography: HtmlContentViewerTypography(
            fontStyle: HtmlContentViewerFontStyle.defaultStyle,
            textSize: HtmlContentViewerLength(fontSize),
          ),
          behavior: HtmlContentViewerBehavior(features: {
            HtmlContentViewerFeature.quoteToggle,
            HtmlContentViewerFeature.mobileResponsiveLayout,
          }),
        ),
      );
}
