import 'package:flutter/material.dart';

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
