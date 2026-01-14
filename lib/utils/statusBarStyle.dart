import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ===============================
/// 1️⃣ 纯数据 & 计算层（核心）
/// ===============================
class StatusBarStyleData {
  final Color backgroundColor;
  final Brightness? iconBrightness;

  final Color? navigationBarColor;
  final Brightness? navigationBarIconBrightness;

  const StatusBarStyleData({
    this.backgroundColor = Colors.transparent,
    this.iconBrightness,
    this.navigationBarColor,
    this.navigationBarIconBrightness,
  });

  /// ✅ 对外暴露的 SystemUiOverlayStyle
  SystemUiOverlayStyle get overlayStyle {
    final Brightness statusIconBrightness =
        iconBrightness ?? _calcBrightness(backgroundColor);

    return SystemUiOverlayStyle(
      statusBarColor: backgroundColor,
      statusBarIconBrightness: statusIconBrightness,
      statusBarBrightness: _invertBrightness(statusIconBrightness),

      systemNavigationBarColor: navigationBarColor ?? Colors.black,
      systemNavigationBarIconBrightness:
          navigationBarIconBrightness ??
          _invertBrightness(statusIconBrightness),

      systemNavigationBarDividerColor: Colors.transparent,
    );
  }

  /// 透明 → 默认黑色图标（系统一致）
  static Brightness _calcBrightness(Color bg) {
    if (bg.opacity == 0) return Brightness.dark;
    return bg.computeLuminance() < 0.5
        ? Brightness.light
        : Brightness.dark;
  }

  static Brightness _invertBrightness(Brightness b) {
    return b == Brightness.light ? Brightness.dark : Brightness.light;
  }
}

/// ===============================
/// 2️⃣ 页面级 Widget（稳定应用层）
/// ===============================
class StatusBarStyle extends StatelessWidget {
  final Widget child;
  final StatusBarStyleData data;
  final bool edgeToEdge;

  const StatusBarStyle({
    super.key,
    required this.child,
    required this.data,
    this.edgeToEdge = true,
  });

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight =
        MediaQuery.of(context).padding.top;

    final SystemUiOverlayStyle style = data.overlayStyle;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: StatusBarScope(
        statusBarHeight: statusBarHeight,
        style: style,
        textColor: data.overlayStyle.statusBarIconBrightness == Brightness.dark
            ? Colors.black
            : Colors.white,
        child: _EdgeToEdgeWrapper(
          enabled: edgeToEdge,
          child: child,
        ),
      ),
    );
  }
}

/// ===============================
/// 3️⃣ Android Edge-to-Edge 控制
/// ===============================
class _EdgeToEdgeWrapper extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const _EdgeToEdgeWrapper({
    required this.child,
    required this.enabled,
  });

  @override
  State<_EdgeToEdgeWrapper> createState() => _EdgeToEdgeWrapperState();
}

class _EdgeToEdgeWrapperState extends State<_EdgeToEdgeWrapper> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!Platform.isAndroid) return;

    if (widget.enabled) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [
          SystemUiOverlay.top,
          SystemUiOverlay.bottom,
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// ===============================
/// 4️⃣ 对外暴露（高度 + style）
/// ===============================
class StatusBarScope extends InheritedWidget {
  final double statusBarHeight;
  final SystemUiOverlayStyle style;
  final Color textColor;
  const StatusBarScope({
    super.key,
    required this.statusBarHeight,
    required this.style,
    required this.textColor,
    required super.child,
  });

  static StatusBarScope of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<StatusBarScope>();
    assert(result != null, 'No StatusBarScope found');
    return result!;
  }

  @override
  bool updateShouldNotify(StatusBarScope oldWidget) {
    return statusBarHeight != oldWidget.statusBarHeight ||
        style != oldWidget.style;
  }
}
