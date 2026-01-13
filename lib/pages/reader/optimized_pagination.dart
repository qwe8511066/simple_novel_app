import 'package:flutter/material.dart';
import 'dart:collection';

/// 页面边界信息，记录每页的起始和结束行索引
class PageBoundary {
  final int startIndex;
  final int endIndex;
  final double height;

  PageBoundary({
    required this.startIndex,
    required this.endIndex,
    required this.height,
  });
}

/// 优化的按需分页引擎，支持虚拟滚动和高效翻页
class OptimizedPaginationEngine {
  final List<String> lines;
  final TextStyle style;
  final Size size;
  final int capacity; // 缓存容量
  final double lineHeightEstimate;

  /// 强制起页的行号集合（通常是每一章标题所在的行号）
  /// 只要遇到这些行，且当前页已有内容，就会强制换页，保证章节标题出现在页首
  final Set<int>? forcedPageStartLineIndices;

  // 页面内容缓存
  final Map<int, List<String>> _pageCache = {};
  // 行高度缓存
  final Map<int, double> _lineHeights = {};
  // 页面边界缓存
  final Map<int, PageBoundary> _pageBoundaries = {};
  // 页面计算状态，避免重复计算
  final Set<int> _calculatedPages = {};

  OptimizedPaginationEngine({
    required this.lines,
    required this.style,
    required this.size,
    this.capacity = 50, // 默认缓存50页
    this.forcedPageStartLineIndices,
  }) : lineHeightEstimate = _estimateLineHeight(style);

  /// 是否需要在当前行强制开启新的一页
  bool _shouldForceNewPageAt(int lineIndex, bool pageHasContent) {
    if (!pageHasContent) return false;
    if (forcedPageStartLineIndices == null || forcedPageStartLineIndices!.isEmpty) {
      return false;
    }
    return forcedPageStartLineIndices!.contains(lineIndex);
  }

  /// 估算单行高度
  static double _estimateLineHeight(TextStyle style) {
    // 使用更准确的方法估算行高，考虑字体大小和行间距
    return (style.fontSize ?? 16.0) * (style.height ?? 1.2);
  }

  /// 获取指定页的内容
  Future<List<String>> getPageContent(int pageIndex) async {
    // 检查缓存
    if (_pageCache.containsKey(pageIndex)) {
      return _pageCache[pageIndex]!;
    }

    // 计算页面内容
    final pageContent = await _computePageContent(pageIndex);
    
    // 存入缓存
    _pageCache[pageIndex] = pageContent;
    _calculatedPages.add(pageIndex);

    // 如果缓存超过容量，移除最久未使用的页面
    if (_pageCache.length > capacity) {
      _evictOldestPage();
    }

    return pageContent;
  }

  /// 计算指定页的内容
  Future<List<String>> _computePageContent(int pageIndex) async {
    // 检查是否已知页面边界
    if (_pageBoundaries.containsKey(pageIndex)) {
      final boundary = _pageBoundaries[pageIndex]!;
      final page = <String>[];
      
      // 添加安全检查，确保起始索引不会是负数
      final safeStartIndex = boundary.startIndex < 0 ? 0 : boundary.startIndex;
      
      for (int i = safeStartIndex; i <= boundary.endIndex && i < lines.length; i++) {
        page.add(lines[i]);
      }
      return page;
    }

    // 如果是第一页，从头开始计算
    if (pageIndex == 0) {
      return _computeFirstPage();
    }

    // 对于非第一页，尝试从临近页面推断
    return _computePageFromNearest(pageIndex);
  }

  /// 计算第一页内容
  Future<List<String>> _computeFirstPage() async {
    final page = <String>[];
    double height = 0;
    int lineIndex = 0;

    while (lineIndex < lines.length) {
      final line = lines[lineIndex];
      final lineHeight = _getLineHeight(lineIndex, line);

      // 如果遇到强制起页行，并且当前页已有内容，则结束当前页
      if (_shouldForceNewPageAt(lineIndex, page.isNotEmpty)) {
        break;
      }
      
      // 检查是否超出页面高度
      if (height + lineHeight > size.height - 32 && page.isNotEmpty) {
        break; // 超出页面高度且页面已有内容，结束当前页
      }
      
      page.add(line);
      height += lineHeight;
      lineIndex++;

      // 定期让出控制权，避免阻塞UI
      if (lineIndex % 500 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    // 记录页面边界
    if (page.isNotEmpty) {
      _pageBoundaries[0] = PageBoundary(
        startIndex: 0,
        endIndex: lineIndex - 1,
        height: height,
      );
    }

    return page;
  }

  /// 从最近的已知页面开始计算目标页面
  Future<List<String>> _computePageFromNearest(int targetPageIndex) async {
    // 找到最近的已计算页面
    int startPageIndex = -1;
    for (int i = targetPageIndex - 1; i >= 0; i--) {
      if (_pageBoundaries.containsKey(i)) {
        startPageIndex = i;
        break;
      }
    }

    // 如果没有找到已计算的页面，从头开始计算（这种情况应该很少发生）
    if (startPageIndex == -1) {
      // 从头计算直到目标页面
      return await _computePageFromBeginning(targetPageIndex);
    }

    // 从已知页面开始计算
    final startBoundary = _pageBoundaries[startPageIndex]!;
    return await _computePageFromStartBoundary(startBoundary, startPageIndex, targetPageIndex);
  }

  /// 从开头计算到目标页面
  Future<List<String>> _computePageFromBeginning(int targetPageIndex) async {
    int currentPageIndex = 0;
    int lineIndex = 0;
    double currentHeight = 0;
    int currentPageStartIndex = 0; // 跟踪当前页面的起始索引

    while (currentPageIndex <= targetPageIndex && lineIndex < lines.length) {
      final line = lines[lineIndex];
      final lineHeight = _getLineHeight(lineIndex, line);

      final bool forceNewPageHere = _shouldForceNewPageAt(lineIndex, currentHeight > 0);

      if ((currentHeight + lineHeight > size.height - 32 || forceNewPageHere) &&
          currentPageIndex < targetPageIndex) {
        // 开始新页面
        _pageBoundaries[currentPageIndex] = PageBoundary(
          startIndex: currentPageStartIndex,
          endIndex: lineIndex - 1,
          height: currentHeight,
        );
        currentPageIndex++;
        currentHeight = 0;
        currentPageStartIndex = lineIndex; // 更新新页面的起始索引
      } else if ((currentHeight + lineHeight > size.height - 32 || forceNewPageHere) &&
          currentPageIndex == targetPageIndex) {
        // 达到目标页面且高度超限，记录边界
        _pageBoundaries[currentPageIndex] = PageBoundary(
          startIndex: currentPageStartIndex,
          endIndex: lineIndex - 1,
          height: currentHeight,
        );
        break;
      }

      currentHeight += lineHeight;
      lineIndex++;

      // 定期让出控制权
      if (lineIndex % 500 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    // 构建目标页面内容
    if (_pageBoundaries.containsKey(targetPageIndex)) {
      final boundary = _pageBoundaries[targetPageIndex]!;
      final page = <String>[];
      for (int i = boundary.startIndex; i <= boundary.endIndex && i < lines.length; i++) {
        page.add(lines[i]);
      }
      return page;
    }

    // 如果没有找到边界，返回空页面
    return [];
  }

  /// 从起始边界计算到目标页面
  Future<List<String>> _computePageFromStartBoundary(
    PageBoundary startBoundary,
    int startPageIndex,
    int targetPageIndex,
  ) async {
    int lineIndex = startBoundary.endIndex + 1;
    double currentHeight = 0;
    int currentPageIndex = startPageIndex + 1;
    int currentPageStartIndex = lineIndex; // 跟踪当前页面的起始索引

    // 跳过已知页面
    while (currentPageIndex < targetPageIndex && lineIndex < lines.length) {
      final line = lines[lineIndex];
      final lineHeight = _getLineHeight(lineIndex, line);

      final bool forceNewPageHere = _shouldForceNewPageAt(lineIndex, currentHeight > 0);

      if (currentHeight + lineHeight > size.height - 32 || forceNewPageHere) {
        // 开始新页面
        _pageBoundaries[currentPageIndex] = PageBoundary(
          startIndex: currentPageStartIndex,
          endIndex: lineIndex - 1, // 当前行还没处理，所以结束索引是上一行
          height: currentHeight,
        );
        currentPageIndex++;
        currentHeight = 0;
        currentPageStartIndex = lineIndex; // 更新新页面的起始索引
        continue; // 不处理当前行，让它在下一个循环中被处理
      }

      currentHeight += lineHeight;
      lineIndex++;
    }

    // 计算目标页面
    final targetPage = <String>[];
    while (lineIndex < lines.length) {
      final line = lines[lineIndex];
      final lineHeight = _getLineHeight(lineIndex, line);

      final bool forceNewPageHere = _shouldForceNewPageAt(lineIndex, targetPage.isNotEmpty);

      if ((currentHeight + lineHeight > size.height - 32 || forceNewPageHere) &&
          targetPage.isNotEmpty) {
        // 页面满了，记录边界
        _pageBoundaries[currentPageIndex] = PageBoundary(
          startIndex: lineIndex - targetPage.length,
          endIndex: lineIndex - 1,
          height: currentHeight - lineHeight, // 不包含当前行的高度
        );
        break;
      }

      targetPage.add(line);
      currentHeight += lineHeight;
      lineIndex++;

      // 定期让出控制权
      if (lineIndex % 500 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (targetPage.isNotEmpty && !_pageBoundaries.containsKey(currentPageIndex)) {
      _pageBoundaries[currentPageIndex] = PageBoundary(
        startIndex: lineIndex - targetPage.length,
        endIndex: lineIndex - 1,
        height: currentHeight,
      );
    }

    return targetPage;
  }

  /// 获取行高度（带缓存）
  double _getLineHeight(int lineIndex, String line) {
    if (_lineHeights.containsKey(lineIndex)) {
      return _lineHeights[lineIndex]!;
    }

    final tp = TextPainter(
      text: TextSpan(text: line, style: style),
      maxLines: null,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 32);

    final height = tp.height;
    _lineHeights[lineIndex] = height;
    
    // 控制缓存大小，避免内存溢出
    if (_lineHeights.length > 10000) {
      // 移除最早的500个条目
      final keys = _lineHeights.keys.toList()..sort();
      for (int i = 0; i < 500 && i < keys.length; i++) {
        _lineHeights.remove(keys[i]);
      }
    }

    return height;
  }

  /// 计算指定页面的起始索引（简化实现）
  int _calculateStartIndexForPage(int pageIndex) {
    if (pageIndex == 0) return 0;

    // 从前面的页面边界推算
    for (int i = pageIndex - 1; i >= 0; i--) {
      if (_pageBoundaries.containsKey(i)) {
        final prevBoundary = _pageBoundaries[i]!;
        return prevBoundary.endIndex + 1;
      }
    }

    // 如果找不到前置边界，估算
    final estimatedLinesPerPage = ((size.height - 32) / lineHeightEstimate).floor();
    return pageIndex * estimatedLinesPerPage;
  }

  /// 获取页面包含的行数（辅助函数）
  int _getPageLineCount(int pageIndex) {
    if (_pageBoundaries.containsKey(pageIndex)) {
      final boundary = _pageBoundaries[pageIndex]!;
      return boundary.endIndex - boundary.startIndex + 1;
    }
    // 估算值
    final estimatedLinesPerPage = ((size.height - 32) / lineHeightEstimate).floor();
    return estimatedLinesPerPage;
  }

  /// 移除最久未使用的页面（LRU策略）
  void _evictOldestPage() {
    if (_pageCache.isEmpty) return;

    // 简单实现：移除第一个页面（实际应用中可以实现更复杂的LRU）
    final oldestKey = _pageCache.keys.first;
    _pageCache.remove(oldestKey);
    _calculatedPages.remove(oldestKey);
  }

  /// 估算总页数
  int estimateTotalPages() {
    if (lines.isEmpty) return 0;

    // 使用更准确的方法估算总页数
    // 首先获取实际计算过的页面行数统计
    final List<int> pageLineCounts = [];
    for (int pageIndex in _pageBoundaries.keys) {
      final boundary = _pageBoundaries[pageIndex]!;
      pageLineCounts.add(boundary.endIndex - boundary.startIndex + 1);
    }

    // 如果有实际计算过的页面，使用平均值
    if (pageLineCounts.isNotEmpty) {
      final averageLinesPerPage = pageLineCounts.reduce((a, b) => a + b) ~/ pageLineCounts.length;
      if (averageLinesPerPage > 0) {
        // 使用更准确的估算，增加5%的缓冲
        return (lines.length / averageLinesPerPage * 1.05).ceil();
      }
    }

    // 否则使用估算值
    final estimatedPageHeight = size.height - 32;
    final estimatedLinesPerPage = (estimatedPageHeight / lineHeightEstimate).floor();

    if (estimatedLinesPerPage <= 0) return 1;
    
    // 使用更准确的估算，增加5%的缓冲
    return (lines.length / estimatedLinesPerPage * 1.05).ceil();
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

  /// 根据行号精确查找所在的页码
  /// 说明：
  /// - 仅依赖实际的行高和分页规则，不依赖估算的总页数
  /// - 在向前遍历行的过程中，顺带填充 _pageBoundaries，后续跳转会更快更准
  Future<int> findPageIndexByLineIndex(int targetLineIndex) async {
    if (lines.isEmpty) return 0;
    if (targetLineIndex <= 0) return 0;
    if (targetLineIndex >= lines.length) {
      // 超出范围时，返回最后一页的索引（需要根据已知边界大致估算）
      if (_pageBoundaries.isNotEmpty) {
        return _pageBoundaries.keys.reduce((a, b) => a > b ? a : b);
      }
      return 0;
    }

    final double maxPageHeight = size.height - 32;

    int pageIndex = 0;
    int lineIndex = 0;
    double currentHeight = 0;
    int currentPageStartIndex = 0;

    while (lineIndex < lines.length) {
      final line = lines[lineIndex];
      final lineHeight = _getLineHeight(lineIndex, line);

      final bool forceNewPageHere = _shouldForceNewPageAt(lineIndex, currentHeight > 0);

      // 如果再加这一行会超出页面高度，或遇到强制起页行，并且当前页已经有内容，则先收一个页面
      if ((currentHeight + lineHeight > maxPageHeight || forceNewPageHere) &&
          currentPageStartIndex <= lineIndex - 1) {
        // 记录当前页边界
        _pageBoundaries[pageIndex] = PageBoundary(
          startIndex: currentPageStartIndex,
          endIndex: lineIndex - 1,
          height: currentHeight,
        );

        // 如果目标行在这个页面范围内，直接返回
        if (targetLineIndex >= currentPageStartIndex && targetLineIndex <= lineIndex - 1) {
          return pageIndex;
        }

        // 开始新的一页
        pageIndex++;
        currentHeight = 0;
        currentPageStartIndex = lineIndex;
      }

      // 此时 lineIndex 属于当前页
      if (lineIndex == targetLineIndex) {
        return pageIndex;
      }

      currentHeight += lineHeight;
      lineIndex++;

      // 避免长时间阻塞 UI
      if (lineIndex % 500 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    // 最后一页边界
    if (!_pageBoundaries.containsKey(pageIndex)) {
      _pageBoundaries[pageIndex] = PageBoundary(
        startIndex: currentPageStartIndex,
        endIndex: lines.length - 1,
        height: currentHeight,
      );
    }

    // 如果目标行在最后一页（常见于 targetLineIndex 接近文件末尾）
    if (targetLineIndex >= currentPageStartIndex && targetLineIndex < lines.length) {
      return pageIndex;
    }

    // 兜底：返回最后一页
    return pageIndex;
  }

  /// 清除所有页面缓存
  void clearCache() {
    _pageCache.clear();
    _pageBoundaries.clear();
  }
  
  /// 只清除页面内容缓存，保留页面边界缓存（用于章节跳转优化）
  void clearPageContentCacheOnly() {
    _pageCache.clear();
    _calculatedPages.clear();
    // 保留 _pageBoundaries 和 _lineHeights，因为这些对跳转准确性很重要
  }
}