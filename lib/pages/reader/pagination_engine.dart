import 'package:flutter/material.dart';

/// 分页后的页面类
/// 表示文本经过分页处理后生成的单个页面
class PaginatedPage {
  /// 页面起始行在原始文本中的索引
  final int startLineIndex;
  /// 页面包含的所有行内容
  final List<String> lines;

  const PaginatedPage({
    required this.startLineIndex,
    required this.lines,
  });
}

/// 分页引擎类
/// 负责将文本按行分割成适合屏幕显示的页面
class PaginationEngine {
  /// 原始文本的行列表
  final List<String> lines;
  /// 文本样式
  final TextStyle style;
  /// 页面尺寸
  final Size size;
  /// 段落间距
  final double paragraphSpacing;

  /// 构造函数
  PaginationEngine(
    this.lines,
    this.style,
    this.size, {
    this.paragraphSpacing = 0,
  });

  /// 简单分页方法
  /// 将文本行列表分割成适合屏幕显示的页面列表
  List<List<String>> paginate() {
    final pages = <List<String>>[]; // 页面列表
    var page = <String>[]; // 当前正在构建的页面
    double height = 0; // 当前页面的累积高度

    // 遍历所有行
    for (final line in lines) {
      // 计算当前行的高度
      final tp = TextPainter(
        text: TextSpan(text: line, style: style),
        maxLines: null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);

      // 如果当前行添加到页面会超出页面高度
      if (height + tp.height > size.height) {
        if (page.isNotEmpty) {
          // 将当前页面添加到页面列表
          pages.add(page);
          // 重置当前页面和高度
          page = [];
          height = 0;
        } else {
          // 如果当前页面为空（单行内容过长），直接添加当前行
          pages.add([line]);
          continue;
        }
      }

      // 将当前行添加到当前页面
      page.add(line);
      // 累加页面高度
      height += tp.height;
    }

    // 将最后一个页面添加到页面列表
    if (page.isNotEmpty) pages.add(page);
    return pages;
  }

  /// 带行索引的分页方法
  /// 调用带条件的分页方法，不指定条件
  List<PaginatedPage> paginateWithLineIndex() {
    return paginateWithLineIndexWhere();
  }

  /// 带行索引和条件的分页方法
  /// 根据指定条件将文本行列表分割成带起始行索引的页面列表
  List<PaginatedPage> paginateWithLineIndexWhere({
    /// 自定义条件函数，判断是否应该开始新页面
    bool Function(String line)? shouldStartNewPage,
  }) {
    final pages = <PaginatedPage>[]; // 带行索引的页面列表
    var page = <String>[]; // 当前正在构建的页面
    var pageStartLineIndex = 0; // 当前页面的起始行索引

    /// 测量指定行列表的总高度
    double _measureLinesHeight(List<String> lines) {
      final tp = TextPainter(
        text: TextSpan(text: lines.join('\n'), style: style),
        maxLines: null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      return tp.height;
    }

    /// 如果当前页面不为空，则将其添加到页面列表
    void _flushPageIfNotEmpty() {
      if (page.isEmpty) return;
      pages.add(PaginatedPage(startLineIndex: pageStartLineIndex, lines: page));
      page = [];
    }

    int lineIndex = 0; // 当前处理的行索引
    while (lineIndex < lines.length) {
      var line = lines[lineIndex]; // 当前处理的行
      // 判断当前行是否满足开始新页面的条件
      final isChapterTitle =
          shouldStartNewPage != null && shouldStartNewPage(line.trim());

      // 如果是章节标题且当前页面不为空，则开始新页面
      if (isChapterTitle && page.isNotEmpty) {
        _flushPageIfNotEmpty();
        pageStartLineIndex = lineIndex;
      }

      // 处理当前行
      while (true) {
        // 将当前行添加到页面
        page.add(line);
        // 测量页面高度
        final h = _measureLinesHeight(page);

        // 如果页面高度不超过屏幕高度，处理下一行
        if (h <= size.height) {
          break;
        }

        // 页面高度超过屏幕高度，移除当前行
        page.removeLast();

        // 如果当前页面不为空
        if (page.isNotEmpty) {
          // 计算剩余空间
          final baseHeight = _measureLinesHeight(page);
          final remaining = size.height - baseHeight;
          if (remaining > 0) {
            // 使用二分查找找到最大的可容纳文本长度
            var lo = 1;
            var hi = line.length;
            var best = 0;
            while (lo <= hi) {
              final mid = (lo + hi) >> 1;
              final prefix = line.substring(0, mid);
              final testLines = [...page, prefix];
              final th = _measureLinesHeight(testLines);
              if (th <= size.height) {
                best = mid;
                lo = mid + 1;
              } else {
                hi = mid - 1;
              }
            }

            // 如果找到可容纳的文本片段
            if (best > 0 && best < line.length) {
              // 将行分割成两部分
              final head = line.substring(0, best);
              final tail = line.substring(best);
              // 将前半部分添加到当前页面
              page.add(head);
              // 保存当前页面
              _flushPageIfNotEmpty();
              // 更新页面起始行索引
              pageStartLineIndex = lineIndex;
              // 处理剩余部分
              line = tail;
              continue;
            }
          }

          // 保存当前页面
          _flushPageIfNotEmpty();
          // 更新页面起始行索引
          pageStartLineIndex = lineIndex;
          continue;
        }

        // 当前页面为空（单行内容过长）
        if (line.isNotEmpty) {
          // 使用二分查找找到最大的可容纳文本长度
          var lo = 1;
          var hi = line.length;
          var best = 0;
          while (lo <= hi) {
            final mid = (lo + hi) >> 1;
            final prefix = line.substring(0, mid);
            final th = _measureLinesHeight([prefix]);
            if (th <= size.height) {
              best = mid;
              lo = mid + 1;
            } else {
              hi = mid - 1;
            }
          }
          // 如果找到可容纳的文本片段
          if (best > 0 && best < line.length) {
            // 将行分割成两部分
            final head = line.substring(0, best);
            final tail = line.substring(best);
            // 将前半部分添加到当前页面
            page.add(head);
            // 保存当前页面
            _flushPageIfNotEmpty();
            // 更新页面起始行索引
            pageStartLineIndex = lineIndex;
            // 处理剩余部分
            line = tail;
            continue;
          }
        }

        // 无法分割行，直接添加到页面
        page.add(line);
        // 保存当前页面
        _flushPageIfNotEmpty();
        // 更新页面起始行索引
        pageStartLineIndex = lineIndex + 1;
        break;
      }

      // 处理下一行
      lineIndex++;
    }

    // 保存最后一个页面
    if (page.isNotEmpty) {
      pages.add(PaginatedPage(startLineIndex: pageStartLineIndex, lines: page));
    }
    return pages;
  }
}
