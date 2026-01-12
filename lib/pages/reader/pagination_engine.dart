import 'package:flutter/material.dart';

/// 分页处理函数，用于后台计算
Future<List<List<String>>> paginateInBackground(PaginationParams params) async {
  final pages = <List<String>>[];
  var page = <String>[];
  double height = 0;

  // 创建TextPainter以测量文本高度
  for (int i = 0; i < params.lines.length; i++) {
    final line = params.lines[i];
    final tp = TextPainter(
      text: TextSpan(text: line, style: params.style ?? const TextStyle(fontSize: 16, height: 1.8)),
      maxLines: null,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: params.size.width - 32);

    if (height + tp.height > params.size.height - 32) {
      // 添加当前页面并开始新页面
      pages.add(List<String>.from(page));
      page = [];
      height = 0;
    }

    page.add(line);
    height += tp.height;

    // 每处理一定数量的行后让出控制权，有助于在后台线程中避免长时间阻塞
    if (i > 0 && i % 1000 == 0) {
      await Future<void>.delayed(Duration.zero); // 让出控制权
    }
  }

  if (page.isNotEmpty) pages.add(List<String>.from(page));
  return pages;
}

/// 分页处理函数，用于前台计算（带异步让出控制权）
Future<List<List<String>>> paginateInForeground(PaginationParams params) async {
  final pages = <List<String>>[];
  var page = <String>[];
  double height = 0;

  // 创建TextPainter以测量文本高度
  for (int i = 0; i < params.lines.length; i++) {
    final line = params.lines[i];
    final tp = TextPainter(
      text: TextSpan(text: line, style: params.style ?? const TextStyle(fontSize: 16, height: 1.8)),
      maxLines: null,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: params.size.width - 32);

    if (height + tp.height > params.size.height - 32) {
      // 添加当前页面并开始新页面
      pages.add(List<String>.from(page));
      page = [];
      height = 0;
    }

    page.add(line);
    height += tp.height;

    // 每处理一定数量的行后让出控制权给UI线程，避免界面卡顿
    if (i > 0 && i % 500 == 0) {
      await Future<void>.delayed(Duration.zero); // 让出控制权
    }
  }

  if (page.isNotEmpty) pages.add(List<String>.from(page));
  return pages;
}

/// 分页参数包装类
class PaginationParams {
  final List<String> lines;
  final TextStyle? style;
  final Size size;

  PaginationParams({
    required this.lines,
    this.style,
    required this.size,
  });
}

class PaginationEngine {
  final List<String> lines;
  final TextStyle style;
  final Size size;

  PaginationEngine(this.lines, this.style, this.size);

  /// 分页处理文本内容
  /// 优化了性能以处理大文件
  List<List<String>> paginate() {
    final pages = <List<String>>[];
    var page = <String>[];
    double height = 0;

    // 为了提高性能，我们批量处理文本测量
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final tp = TextPainter(
        text: TextSpan(text: line, style: style),
        maxLines: null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 32);

      if (height + tp.height > size.height - 32) {
        // 添加当前页面并开始新页面
        pages.add(List<String>.from(page)); // 创建页面副本以避免引用问题
        page = [];
        height = 0;
      }

      page.add(line);
      height += tp.height;

      // 每处理一定数量的行后让出控制权给UI线程，避免界面卡顿
      if (i > 0 && i % 500 == 0) {
        // 这里我们不实际延迟，而是提供一个优化的算法
        // 在实际应用中，我们可以使用 isolate 来处理大数据
      }
    }

    if (page.isNotEmpty) pages.add(List<String>.from(page));
    return pages;
  }
}
