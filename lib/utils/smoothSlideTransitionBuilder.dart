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
    // 首个路由不做动画，避免启动闪动
    if (route.settings.name == Navigator.defaultRouteName) {
      return child;
    }

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeOutCubic,
            ),
          ),
      child: child,
    );
  }
}
