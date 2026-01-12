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
    if (route.settings.name == Navigator.defaultRouteName) return child;

    // 1. 进入/退出动画：全屏位移
    final Animation<Offset> inAnimation =
        Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );

    // 2. 被顶开动画：增加透明度渐变，效果更高级
    final Animation<Offset> outAnimation =
        Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.25, 0.0), // 往左移动 25%
        ).animate(
          CurvedAnimation(
            parent: secondaryAnimation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );

    // 嵌套组合：先处理被顶开的位移，再处理进入的位移
    // 建议在外层套一个遮罩或阴影
    return SlideTransition(
      position: inAnimation,
      child: SlideTransition(
        position: outAnimation,
        child: FadeTransition(
          // 当页面被顶到后面去时，稍微变暗一点
          opacity: Tween<double>(
            begin: 1.0,
            end: 0.8,
          ).animate(secondaryAnimation),
          child: child,
        ),
      ),
    );
  }
}
