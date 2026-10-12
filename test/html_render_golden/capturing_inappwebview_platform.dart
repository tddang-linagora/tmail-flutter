import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The webview packages are reached through `core`, which owns the dependency.
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview/flutter_inappwebview.dart' show InAppWebViewController;
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

/// Stands in for the webview plugin: the real viewer widget builds its
/// document and hands it to `loadData`, which is recorded instead of rendered.
class CapturingInAppWebViewPlatform extends InAppWebViewPlatform {
  static String? _data;

  static void install() =>
      InAppWebViewPlatform.instance = CapturingInAppWebViewPlatform();

  static String takeData() {
    final data = _data;
    if (data == null) throw StateError('viewer never called loadData');
    _data = null;
    return data;
  }

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _CapturingWidget(params);
}

class _CapturingWidget extends PlatformInAppWebViewWidget {
  _CapturingWidget(PlatformInAppWebViewWidgetCreationParams params)
      : super.implementation(params);

  bool _created = false;

  @override
  Widget build(BuildContext context) {
    if (!_created) {
      _created = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => params.onWebViewCreated
          ?.call(controllerFromPlatform(_CapturingController())));
    }
    return const SizedBox.expand();
  }

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      InAppWebViewController.fromPlatform(platform: controller) as T;

  @override
  void dispose() {}
}

/// Every controller call is a no-op except `loadData`, whose `data` is kept.
class _CapturingController extends Fake implements PlatformInAppWebViewController {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadData) {
      CapturingInAppWebViewPlatform._data =
          invocation.namedArguments[#data] as String;
    }
    return Future<void>.value();
  }
}
