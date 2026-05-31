import 'package:blur/blur.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

const String _kNativeLiquidGlassViewType = 'eros_fe/native_liquid_glass';

/// Small iOS-native Liquid Glass host.
///
/// On iOS this embeds a UIKit [UIVisualEffectView] backed by iOS 26's
/// `UIGlassEffect` when it is available at runtime. Older iOS versions and
/// non-iOS targets fall back to the existing Flutter blur implementation.
class NativeLiquidGlass extends StatelessWidget {
  const NativeLiquidGlass({
    super.key,
    required this.child,
    this.blur = 10,
    this.blurColor,
    this.colorOpacity = 0.0,
    this.cornerRadius = 0,
    this.useNative = true,
  });

  final Widget child;
  final double blur;
  final Color? blurColor;
  final double colorOpacity;
  final double cornerRadius;
  final bool useNative;

  bool get _canUseNative =>
      useNative && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final fallbackColor =
        blurColor ?? CupertinoTheme.of(context).barBackgroundColor;

    if (!_canUseNative) {
      return Blur(
        blur: blur,
        blurColor: fallbackColor,
        colorOpacity: colorOpacity,
        borderRadius: BorderRadius.circular(cornerRadius),
        child: child,
      );
    }

    final resolvedColor = CupertinoDynamicColor.resolve(fallbackColor, context);
    final overlayOpacity = (0.08 + colorOpacity * 0.18).clamp(0.08, 0.30);
    final overlayColor = resolvedColor.withValues(alpha: overlayOpacity);

    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(cornerRadius),
              child: UiKitView(
                viewType: _kNativeLiquidGlassViewType,
                hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                creationParamsCodec: const StandardMessageCodec(),
                creationParams: <String, Object?>{
                  'style': 'regular',
                  'fallbackStyle': 'systemUltraThinMaterial',
                  'tintColor': _colorToArgb32(resolvedColor),
                  'overlayColor': _colorToArgb32(overlayColor),
                  'cornerRadius': cornerRadius,
                  'isInteractive': false,
                },
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }

  int _colorToArgb32(Color color) {
    // Keep compatibility with Flutter versions before Color.toARGB32().
    // ignore: deprecated_member_use
    return color.value;
  }
}
