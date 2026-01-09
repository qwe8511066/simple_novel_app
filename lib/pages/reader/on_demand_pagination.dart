import 'package:flutter/material.dart';
import 'dart:collection';

/// 页面缓存类，用于存储已计算的页面
class PageCache {
  final Map<int, List<String>> _cache = <int, List<String>>{};
  final int capacity;

  PageCache({this.capacity = 50}); // 默认缓存50页

  List<String>? get(int index) => _cache[index];

  void put(int index, List<String> page) {
    if (_cache.length >= capacity) {
      // 移除最早添加的项
      _cache.remove(_cache.keys.first);
    }
    _cache[index] = page;
  }

  void clear() => _cache.clear();
}

/// 按需分页引擎，支持虚拟滚动
class OnDemandPaginationEngine {
  final List<String> lines;
  final TextStyle style;
  final Size size;
  final PageCache cache;
  final double lineHeightEstimate;

  OnDemandPaginationEngine({
    required this.lines,
    required this.style,
    required this.size,
    PageCache? cache,
  }) : cache = cache ?? PageCache(),
       lineHeightEstimate = _estimateLineHeight(style);

  /// 估算单行高度
  static double _estimateLineHeight(TextStyle style) {
    return (style.fontSize ?? 16.0) * (style.height ?? 1.8);
  }

  /// 获取指定页的内容
  Future<List<String>> getPageContent(int pageIndex) async {
    // 首先检查缓存
    final cachedPage = cache.get(pageIndex);
    if (cachedPage != null) {
      return cachedPage;
    }

    // 计算该页内容
    final pageContent = await _computePageContent(pageIndex);
    
    // 存入缓存
    cache.put(pageIndex, pageContent);
    
    return pageContent;
  }

  /// 计算指定页的内容
  Future<List<String>> _computePageContent(int pageIndex) async {
    int currentLineIndex = 0;
    
    // 如果不是第一页，需要从前面的页面找到起始位置
    if (pageIndex > 0) {
      currentLineIndex = await _findLineIndexForPage(pageIndex);
    }

    // 从找到的位置开始构建目标页面
    return _buildPageFromLine(currentLineIndex, pageIndex);
  }

  /// 找到指定页的起始行索引
  Future<int> _findLineIndexForPage(int targetPageIndex) async {
    int lineIndex = 0;
    int currentPageIndex = 0;
    double height = 0;

    while (currentPageIndex < targetPageIndex && lineIndex < lines.length) {
      final line = lines[lineIndex];
      final tp = TextPainter(
        text: TextSpan(text: line, style: style),
        maxLines: null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 32);

      if (height + tp.height > size.height - 32) {
        // 开始新页面
        currentPageIndex++;
        height = 0;
        
        if (currentPageIndex == targetPageIndex) {
          // 找到了目标页的起始位置
          break;
        }
      }

      height += tp.height;
      lineIndex++;

      // 定期让出控制权，避免阻塞UI
      if (lineIndex % 500 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    return lineIndex;
  }

  /// 从指定行开始构建页面
  Future<List<String>> _buildPageFromLine(int startLineIndex, int targetPageIndex) async {
    final page = <String>[];
    double height = 0;
    int lineIndex = startLineIndex;

    while (lineIndex < lines.length) {
      final line = lines[lineIndex];
      final tp = TextPainter(
        text: TextSpan(text: line, style: style),
        maxLines: null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 32);

      // 检查是否超出页面高度
      if (height + tp.height > size.height - 32 && page.isNotEmpty) {
        // 超出页面高度且页面已有内容，结束当前页
        break;
      }

      page.add(line);
      height += tp.height;
      lineIndex++;

      // 定期让出控制权，避免阻塞UI
      if (lineIndex % 500 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    return page;
  }

  /// 估算总页数
  int estimateTotalPages() {
    if (lines.isEmpty) return 0;
    
    // 使用估算值来快速计算总页数
    final estimatedPageHeight = size.height - 32;
    final estimatedLinesPerPage = (estimatedPageHeight / lineHeightEstimate).floor();
    
    if (estimatedLinesPerPage <= 0) return 1;
    
    return (lines.length / estimatedLinesPerPage).ceil();
  }

  /// 预加载相邻页面
  Future<void> preloadAdjacentPages(int currentPageIndex, {int preloadCount = 3}) async {
    final futures = <Future<void>>[];

    for (int offset = 1; offset <= preloadCount; offset++) {
      // 预加载下一页
      if (currentPageIndex + offset < estimateTotalPages()) {
        futures.add(
          Future.microtask(() => getPageContent(currentPageIndex + offset))
        );
      }

      // 预加载上一页
      if (currentPageIndex - offset >= 0) {
        futures.add(
          Future.microtask(() => getPageContent(currentPageIndex - offset))
        );
      }
    }

    await Future.wait(futures);
  }
}