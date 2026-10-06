import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Protects Android routes and overlays from navigation bars and side cutouts.
/// App bars and existing SafeAreas continue to handle the status bar inset.
class AppSystemInsets extends StatelessWidget {
  const AppSystemInsets({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.platform != TargetPlatform.android) return child;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          child: Theme(
            data: theme.copyWith(
              appBarTheme: theme.appBarTheme.copyWith(
                // Let the app bar draw behind the status bar. Only change
                // icon brightness, without invoking legacy bar color setters.
                systemOverlayStyle: SystemUiOverlayStyle(
                  statusBarIconBrightness:
                      ThemeData.estimateBrightnessForColor(
                            theme.appBarTheme.backgroundColor ??
                                theme.colorScheme.surface,
                          ) ==
                          Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
                ),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
