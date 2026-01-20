import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 左右翻页动画（默认）
/// 进入动画：从右侧滑入；退出动画：向左侧滑出并渐隐
class HorizontalPageTurnAnimation extends PageTransitionsBuilder {
  const HorizontalPageTurnAnimation();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 如果是默认路由（首页），不应用动画
    if (route.settings.name == Navigator.defaultRouteName) return child;

    // 进入动画：新页面从右侧滑入
    final Animation<Offset> inAnimation =
        Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
            reverseCurve: Curves.easeInOut,
          ),
        );

    // 退出动画：当前页面向左侧滑出
    final Animation<Offset> outAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(-1.0, 0.0)).animate(
          CurvedAnimation(
            parent: secondaryAnimation,
            curve: Curves.easeInOut,
            reverseCurve: Curves.easeInOut,
          ),
        );

    // 使用Stack实现页面切换效果
    return Stack(
      children: [
        // 退出的页面（滑出并淡出）
        SlideTransition(
          position: outAnimation,
          child: FadeTransition(
            opacity: Tween<double>(
              begin: 1.0,
              end: 0.0,
            ).animate(secondaryAnimation),
            child: child,
          ),
        ),
        // 进入的新页面（滑入并淡入）
        SlideTransition(
          position: inAnimation,
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(animation),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// 翻页效果裁剪器：用于裁剪翻页后剩余的页面部分
class _CurlRemainClipper extends CustomClipper<Path> {
  // 翻页进度（0.0-1.0）
  final double progress;
  // 折叠宽度
  final double foldWidth;

  _CurlRemainClipper({required this.progress, required this.foldWidth});

  @override
  Path getClip(Size size) {
    // 确保进度和折叠宽度在有效范围内
    final p = progress.clamp(0.0, 1.0);
    final fw = foldWidth.clamp(0.0, size.width);
    // 计算折叠边缘的X坐标
    final edgeX = size.width - fw;
    // 计算贝塞尔曲线的振幅，用于模拟翻页的弯曲效果
    final amp = (fw * 0.18 * (1.0 - p)).clamp(0.0, fw);

    // 创建裁剪路径
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(edgeX, 0);
    // 使用二次贝塞尔曲线创建翻页的弯曲效果
    path.quadraticBezierTo(edgeX + amp, size.height * 0.5, edgeX, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _CurlRemainClipper oldClipper) {
    // 当进度或折叠宽度变化时，重新裁剪
    return oldClipper.progress != progress || oldClipper.foldWidth != foldWidth;
  }
}

/// 翻页效果裁剪器：用于裁剪翻页时折叠的页面部分
class _CurlFoldClipper extends CustomClipper<Path> {
  // 翻页进度（0.0-1.0）
  final double progress;
  // 折叠宽度
  final double foldWidth;

  _CurlFoldClipper({required this.progress, required this.foldWidth});

  @override
  Path getClip(Size size) {
    // 确保进度和折叠宽度在有效范围内
    final p = progress.clamp(0.0, 1.0);
    final fw = foldWidth.clamp(0.0, size.width);
    // 计算折叠边缘的X坐标
    final edgeX = size.width - fw;
    // 计算贝塞尔曲线的振幅，用于模拟翻页的弯曲效果
    final amp = (fw * 0.18 * (1.0 - p)).clamp(0.0, fw);

    // 创建裁剪路径
    final path = Path();
    path.moveTo(edgeX, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(edgeX, size.height);
    // 使用二次贝塞尔曲线创建翻页的弯曲效果
    path.quadraticBezierTo(edgeX + amp, size.height * 0.5, edgeX, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _CurlFoldClipper oldClipper) {
    // 当进度或折叠宽度变化时，重新裁剪
    return oldClipper.progress != progress || oldClipper.foldWidth != foldWidth;
  }
}

/// 覆盖式翻页动画（阅读 / 工具类 App 推荐）
///
/// 特点：
/// - 新页面：右侧滑入 + 轻微放大
/// - 旧页面：轻微后退（secondaryAnimation）
/// - 阴影：PhysicalModel（性能优于 BoxShadow）
/// - 首页不参与动画
class CoverPageTurnAnimation extends PageTransitionsBuilder {
  const CoverPageTurnAnimation();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 首页不做动画
    if (route.settings.name == Navigator.defaultRouteName) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.fastOutSlowIn,
      reverseCurve: Curves.easeIn,
    );
    final behind = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOut,
    );
    final slide = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(curved);
    final scaleIn = Tween<double>(begin: 0.97, end: 1.0).animate(curved);
    final scaleBehind = Tween<double>(begin: 1.0, end: 0.98).animate(behind);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final isDone = animation.value == 1.0;
        return RepaintBoundary(
          child: Transform.scale(
            scale: isDone ? 1.0 : scaleBehind.value,
            child: Transform.translate(
              offset: isDone ? Offset.zero : slide.value,
              child: Transform.scale(
                scale: isDone ? 1.0 : scaleIn.value,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    boxShadow: isDone
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 12,
                              spreadRadius: 2,
                              offset: const Offset(0, 3),
                            ),
                          ],
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 仿真翻页动画
/// 新页面滑入时伴随微小的 Y 轴旋转；旧页面滑出时亦带 Y 轴旋转和渐隐
class SimulatedPageTurnAnimation extends PageTransitionsBuilder {
  const SimulatedPageTurnAnimation();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 如果是默认路由（首页），不应用动画
    if (route.settings.name == Navigator.defaultRouteName) return child;

    // 进入动画：新页面从右滑入，并从 0.2 弧度旋转到 0
    final inOffsetAnimation =
        Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
            reverseCurve: Curves.easeInOut,
          ),
        );

    // 进入旋转动画：模拟翻页时的纸张旋转效果
    final inRotationAnimation = Tween<double>(begin: 0.2, end: 0.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOut,
        reverseCurve: Curves.easeInOut,
      ),
    );

    // 退出动画：当前页面向左滑出
    final outOffsetAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(-0.5, 0.0)).animate(
          CurvedAnimation(
            parent: secondaryAnimation,
            curve: Curves.easeInOut,
            reverseCurve: Curves.easeInOut,
          ),
        );

    // 退出旋转动画：当前页面翻出的效果
    final outRotationAnimation = Tween<double>(begin: 0.0, end: -0.2).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeInOut,
        reverseCurve: Curves.easeInOut,
      ),
    );

    // 退出淡出动画：增强翻页效果
    final outOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeInOut,
        reverseCurve: Curves.easeInOut,
      ),
    );

    // 使用Stack实现页面切换效果
    return Stack(
      children: [
        // 当前页面滑出并翻转淡出
        SlideTransition(
          position: outOffsetAnimation,
          child: Transform(
            alignment: Alignment.centerRight,
            transform: Matrix4.identity()..rotateY(outRotationAnimation.value),
            child: FadeTransition(opacity: outOpacityAnimation, child: child),
          ),
        ),
        // 新页面滑入并从左侧（Y 轴）旋转
        SlideTransition(
          position: inOffsetAnimation,
          child: Transform(
            alignment: Alignment.centerLeft,
            transform: Matrix4.identity()..rotateY(inRotationAnimation.value),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// 翻页动画工具类：根据动画名称返回对应的 PageTransitionsBuilder
class ReaderTurnAnimationUtils {
  /// 根据动画名称获取对应的翻页动画实现
  /// [animationName] - 动画名称，可选值：'左右翻页'、'覆盖翻页'、'仿真翻页'
  static PageTransitionsBuilder getAnimation(String animationName) {
    switch (animationName) {
      case '左右翻页':
        return const HorizontalPageTurnAnimation();
      case '覆盖翻页':
        return const CoverPageTurnAnimation();
      case '仿真翻页':
        return const SimulatedPageTurnAnimation();
      default:
        // 默认使用左右翻页动画
        return const HorizontalPageTurnAnimation();
    }
  }
}

/// 阅读页面翻页效果包装器：基于 PageController 的 AnimatedBuilder 包裹每页内容
/// 根据 animationName 决定效果（覆盖、仿真、滑动）
class ReaderTurnEffects {
  /// 包装阅读页面内容，添加翻页效果
  /// [animationName] - 动画名称
  /// [controller] - 页面控制器
  /// [index] - 当前页面索引
  /// [child] - 页面内容
  static Widget wrap({
    required String animationName,
    required PageController controller,
    required int index,
    required Widget child,
  }) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, c) {
        // 获取当前页面位置（考虑控制器是否可用）
        final page = controller.hasClients && controller.position.haveDimensions
            ? (controller.page ?? controller.initialPage.toDouble())
            : controller.initialPage.toDouble();

        // 根据动画名称选择对应的包装方法
        if (animationName == '覆盖翻页') {
          return _wrapCover(
            context: context,
            child: c!,
            page: page,
            index: index,
          );
        }
        if (animationName == '仿真翻页') {
          return _wrapCurl(
            context: context,
            child: c!,
            page: page,
            index: index,
          );
        }
        // 默认使用左右滑动效果
        return _wrapHorizontal(
          context: context,
          child: c!,
          page: page,
          index: index,
        );
      },
    );
  }

  /// 判断页面是否已经稳定（停止滚动）
  /// [page] - 当前页面位置
  static bool _isSettled(double page) {
    final nearest = page.roundToDouble();
    // 如果页面位置与最近的整数页面差值小于0.02，则认为已经稳定
    return (page - nearest).abs() < 0.02;
  }

  static double _stabilizePage(double page) {
    return page;
  }

  /// 包装左右滑动效果
  /// [context] - 上下文
  /// [child] - 页面内容
  /// [page] - 当前页面位置
  /// [index] - 当前页面索引
  static Widget _wrapHorizontal({
    required BuildContext context,
    required Widget child,
    required double page,
    required int index,
  }) {
    // 如果页面已经稳定，直接返回内容
    if (_isSettled(page)) return child;

    // 获取屏幕宽度
    final w = MediaQuery.of(context).size.width;
    // 计算当前页面与目标页面的差值（限制在-1.0到1.0之间）
    final delta = (page - index).clamp(-1.0, 1.0);
    // 计算水平偏移量，用于模拟滑动时的页面位移
    final translateX = delta * w * 0.02;

    // 应用水平位移
    return Transform.translate(offset: Offset(translateX, 0), child: child);
  }

  /// 包装覆盖翻页效果
  /// [context] - 上下文
  /// [child] - 页面内容
  /// [page] - 当前页面位置
  /// [index] - 当前页面索引
  static Widget _wrapCover({
    required BuildContext context,
    required Widget child,
    required double page,
    required int index,
  }) {
    final stablePage = _stabilizePage(page);
    final nearest = stablePage.roundToDouble();
    final settleDistance = (stablePage - nearest).abs();
    final settleDamp = (settleDistance / 0).clamp(0.0, 1.0);

    final rawDelta = stablePage - index;
    if (rawDelta.abs() > 1.0) return child;

    final w = MediaQuery.of(context).size.width;
    final delta = rawDelta.clamp(-1.0, 1.0);
    final t = (delta.abs() * settleDamp).clamp(0.0, 1.0);
    final judgeT = t > 0.0001;
    final isCurrent = delta >= 0;

    final outgoingScale = isCurrent ? (1.0 - (0.03 * t)) : 1.0;
    final incomingX = isCurrent ? 0.0 : (delta * w * settleDamp);
    final incomingShadow =
        isCurrent ? 0.0 : (0.36 * (1.0 - t)).clamp(0.0, 0.36);

    final rightShadeOpacity =
        isCurrent ? (0.22 * (1.0 - t)).clamp(0.0, 0.22) : 0.0;
    final rightEdgeOpacity =
        isCurrent ? (0.14 * (1.0 - t)).clamp(0.0, 0.14) : 0.0;

    return RepaintBoundary(
      child: ClipRect(
        child: Transform.translate(
          offset: Offset(incomingX, 0),
          child: Transform.scale(
            alignment: Alignment.centerLeft,
            scale: outgoingScale,
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: incomingShadow <= 0.0001
                    ? const []
                    : [
                        BoxShadow(
                          color: Colors.transparent,
                          blurRadius: 0,
                          spreadRadius: 2,
                          offset: Offset(w, 0),
                        ),
                      ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: judgeT ? 18 : 0,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: rightShadeOpacity <= 0.0001 ? 0.0 : 1.0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                              colors: [
                                Colors.black.withOpacity(rightShadeOpacity),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: judgeT ? 2 : 0,
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withOpacity(rightEdgeOpacity),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -6,
                    top: 0,
                    bottom: 0,
                    width: judgeT ? 6 : 0,
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 包装仿真翻页效果
  /// [context] - 上下文
  /// [child] - 页面内容
  /// [page] - 当前页面位置
  /// [index] - 当前页面索引
  static Widget _wrapCurl({
    required BuildContext context,
    required Widget child,
    required double page,
    required int index,
  }) {
    // 如果页面已经稳定，直接返回内容
    if (_isSettled(page)) return child;

    // 获取屏幕宽度
    final w = MediaQuery.of(context).size.width;
    // 计算当前页面与目标页面的差值（限制在-1.0到1.0之间）
    final delta = (page - index).clamp(-1.0, 1.0);
    // 获取差值的绝对值
    final t = delta.abs();
    // 判断是当前页面还是下一页
    final current = delta >= 0;

    // 计算翻页进度
    final progress = current ? t : (1.0 - t);
    // 如果进度接近0或1，直接返回内容
    if (progress <= 0.0001) return child;
    if (progress >= 0.9999) return child;

    // 应用缓动曲线，使翻页效果更自然
    final curve = Curves.easeOutCubic.transform(progress);
    // 计算折叠宽度
    final foldWidth = (w * (0.28 + 0.12 * curve)).clamp(0.0, w);
    // 计算旋转角度
    final rot = -math.pi * 0.92 * curve;
    // 设置透视值，增强3D效果
    final perspective = 0.0018;

    // 如果是新页面（向左翻页）
    if (!current) {
      return ClipRect(
        child: Align(
          alignment: Alignment.centerRight,
          widthFactor: curve,
          child: child,
        ),
      );
    }

    // 计算各种效果的透明度
    final shadowOpacity = (0.42 * curve).clamp(0.0, 0.42);
    final highlightOpacity = (0.22 * (1.0 - curve)).clamp(0.0, 0.22);
    final edgeOpacity = (0.26 * curve).clamp(0.0, 0.26);
    // 设置纸张颜色
    final paperColor = const Color(0xFFF3EAD7);

    // 构建翻页效果
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 裁剪剩余页面部分
          ClipPath(
            clipper: _CurlRemainClipper(progress: curve, foldWidth: foldWidth),
            child: child,
          ),
          // 添加折叠边缘的阴影效果
          Positioned(
            right: foldWidth - 1,
            top: 0,
            bottom: 0,
            width: 10,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [
                      Colors.black.withOpacity(edgeOpacity),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 构建折叠部分
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: foldWidth,
            child: ClipPath(
              clipper: _CurlFoldClipper(progress: curve, foldWidth: foldWidth),
              child: Transform(
                alignment: Alignment.centerRight,
                // 设置透视和旋转效果
                transform: Matrix4.identity()
                  ..setEntry(3, 2, perspective)
                  ..rotateY(rot),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 纸张颜色和渐变
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: paperColor,
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            paperColor.withOpacity(1.0),
                            paperColor.withOpacity(0.92),
                          ],
                        ),
                      ),
                    ),
                    // 阴影效果
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withOpacity(shadowOpacity),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    // 高光效果
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [
                            Colors.white.withOpacity(highlightOpacity),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
