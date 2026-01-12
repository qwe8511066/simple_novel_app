import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 页面级状态栏样式（稳定版）
///
/// 用法：
/// StatusBarStyle(
///   backgroundColor: Colors.black,
///   child: Scaffold(...)
/// )
class StatusBarStyle extends StatelessWidget {
  final Widget child;

  final Color backgroundColor;
  final bool autoBrightness;
  final Brightness? iconBrightness;

  final Color? navigationBarColor;
  final Brightness? navigationBarIconBrightness;
  final bool edgeToEdge;

  const StatusBarStyle({
    super.key,
    required this.child,
    this.backgroundColor = Colors.transparent,
    this.autoBrightness = true,
    this.iconBrightness,
    this.navigationBarColor,
    this.navigationBarIconBrightness,
    this.edgeToEdge = true,
  });

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(
      context,
    ).padding.top; // ✅ 唯一正确来源

    final Brightness statusIconBrightness =
        iconBrightness ?? _calcBrightness(backgroundColor);

    final style = SystemUiOverlayStyle(
      statusBarColor: backgroundColor,
      statusBarIconBrightness: statusIconBrightness,
      statusBarBrightness: _invertBrightness(statusIconBrightness),

      systemNavigationBarColor: navigationBarColor ?? Colors.black,
      systemNavigationBarIconBrightness:
          navigationBarIconBrightness ??
          _invertBrightness(statusIconBrightness),

      systemNavigationBarDividerColor: Colors.transparent,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: StatusBarScope(
        statusBarHeight: statusBarHeight,
        child: _EdgeToEdgeWrapper(enabled: edgeToEdge, child: child),
      ),
    );
  }

  static Brightness _calcBrightness(Color bg) {
    if (bg.opacity == 0) {
      // 透明状态栏：默认黑色图标（符合系统默认 + 主流 App）
      return Brightness.dark;
    }
    return bg.computeLuminance() < 0.5 ? Brightness.light : Brightness.dark;
  }

  static Brightness _invertBrightness(Brightness b) {
    return b == Brightness.light ? Brightness.dark : Brightness.light;
  }
}

class _EdgeToEdgeWrapper extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const _EdgeToEdgeWrapper({required this.child, required this.enabled});

  @override
  State<_EdgeToEdgeWrapper> createState() => _EdgeToEdgeWrapperState();
}

class _EdgeToEdgeWrapperState extends State<_EdgeToEdgeWrapper> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (Platform.isAndroid && widget.enabled) {
      // 只在页面进入时设置一次
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class StatusBarScope extends InheritedWidget {
  final double statusBarHeight;

  const StatusBarScope({
    super.key,
    required this.statusBarHeight,
    required super.child,
  });

  static StatusBarScope of(BuildContext context) {
    final StatusBarScope? result = context
        .dependOnInheritedWidgetOfExactType<StatusBarScope>();
    assert(result != null, 'No StatusBarScope found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(StatusBarScope oldWidget) {
    return statusBarHeight != oldWidget.statusBarHeight;
  }
}
