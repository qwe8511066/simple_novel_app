import 'package:flutter/material.dart';

class SmoothSlideTransitionBuilder extends PageTransitionsBuilder {
  const SmoothSlideTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 首个路由不加动画
    if (route.settings.name == Navigator.defaultRouteName) {
      return child;
    }

    final inAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutCubic,
      ),
    );

    final outAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.25, 0.0), // 轻微左移，防闪
    ).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutCubic,
      ),
    );

    return Stack(
      children: [
        SlideTransition(
          position: outAnimation,
          child: child,
        ),
        SlideTransition(
          position: inAnimation,
          child: child,
        ),
      ],
    );
  }
}
