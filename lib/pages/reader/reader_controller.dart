import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'pagination_cache.dart';
import 'optimized_pagination.dart';

// 章节信息类
class ChapterInfo {
  final String title;
  final int lineIndex;
  
  ChapterInfo({required this.title, required this.lineIndex});
}

class ReaderController extends ChangeNotifier {
  final File utf8File;
  final String? novelTitle;
  
  // 优化的按需分页引擎
  OptimizedPaginationEngine? _paginationEngine;
  List<String>? _lines;
  int? _estimatedTotalPages;
  bool _isLoading = false;

  // 记录最近一次用于分页的样式和尺寸，方便在章节解析完成后重建分页引擎
  TextStyle? _lastStyle;
  Size? _lastSize;
  
  // 快速加载相关变量
  String? _firstScreenContent;
  bool _firstScreenLoaded = false;
  bool _fullContentLoaded = false;
  
  // 章节信息
  List<ChapterInfo>? _chapters;
  bool _chaptersLoaded = false;
  
  // 标记：分页引擎是否已经基于章节锚点重建完成
  // 这个标记用于确保恢复逻辑在正确的时机执行
  bool _paginationRebuiltWithChapters = false;

  ReaderController(this.utf8File, {this.novelTitle});

  bool get isLoading => _isLoading;
  
  bool get firstScreenLoaded => _firstScreenLoaded;
  bool get fullContentLoaded => _fullContentLoaded;
  bool get chaptersLoaded => _chaptersLoaded;
  String? get firstScreenContent => _firstScreenContent;
  List<ChapterInfo>? get chapters => _chapters;

  /// 流式加载文本内容（不再使用旧的完整分页缓存，避免与章节锚点分页架构冲突）
  Future<void> load(Size size, TextStyle style) async {
    if (_isLoading) return; // 防止重复加载
    
    _isLoading = true;
    
    try {
      // 记录最新的分页样式和尺寸
      _lastStyle = style;
      _lastSize = size;

      // 流式读取文件内容
      _lines = <String>[];
      int lineCount = 0;
      await for (String line in utf8File.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
        _lines!.add(line);
        lineCount++;
        
        // 每处理一定数量的行后让出控制权给UI线程
        if (lineCount % 500 == 0) {
          await Future<void>.delayed(Duration.zero);
          
          // 在加载过程中持续估算总页数，让用户感觉加载更快
          if (_paginationEngine == null && _lines!.length > 100) {
            _paginationEngine = OptimizedPaginationEngine(
              lines: _lines!,
              style: style,
              size: size,
            );
          }
          _estimatedTotalPages = _paginationEngine?.estimateTotalPages() ?? (lineCount ~/ 20); // 估算
          notifyListeners(); // 更新UI显示进度
        }
      }

      // 创建按需分页引擎（初始时还不知道章节锚点）
      _paginationEngine = OptimizedPaginationEngine(
        lines: _lines!,
        style: style,
        size: size,
      );

      // 估算总页数
      _estimatedTotalPages = _paginationEngine!.estimateTotalPages();

      // 不保存完整分页到缓存，而是仅缓存原始文本内容
      // 这样可以更快地初始化
      
      _fullContentLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('加载文件失败: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// 获取指定页面内容（按需加载）
  Future<String> getPageContentAsync(int index) async {
    if (_paginationEngine != null && index >= 0) {
      try {
        final pageContent = await _paginationEngine!.getPageContent(index);
        // 如果获取到内容，说明页面有效，可能需要更新估算的总页数
        if (pageContent.isNotEmpty) {
          if (index >= (_estimatedTotalPages ?? 0)) {
            _estimatedTotalPages = index + 1;
            notifyListeners();
          }
          return pageContent.join('\n');
        }
        // 如果页面内容为空，尝试更新总页数为当前索引
        if (index > (_estimatedTotalPages ?? 0)) {
          _estimatedTotalPages = index;
          notifyListeners();
        }
      } catch (e) {
        debugPrint('获取页面内容失败: $e');
      }
    }
    return '';
  }

  /// 获取总页数（带缓冲，用于PageView）
  int get totalPages => (_estimatedTotalPages ?? 0) + 100; // 增加100页的缓冲，确保用户可以继续翻页
  
  /// 获取实际总页数（不带缓冲，用于显示）
  int get actualTotalPages => _estimatedTotalPages ?? 0;

  /// 快速获取文件开头内容以立即显示首屏
  Future<String> getFirstScreenContent(Size size, TextStyle style) async {
    if (_firstScreenContent != null) {
      return _firstScreenContent!;
    }
    
    try {
      // 只读取文件开头的10KB内容，避免读取整个文件
      final raf = await utf8File.open(mode: FileMode.read);
      final headerBytes = await raf.read(10240);
      await raf.close();
      
      // 解码为字符串
      String headerContent = utf8.decode(headerBytes);
      
      // 将内容分割为行
      final lines = LineSplitter().convert(headerContent);
      
      // 快速分页以获取第一页内容
      final firstPageLines = _getPageLines(lines, size, style);
      _firstScreenContent = firstPageLines.join('\n');
      _firstScreenLoaded = true;
      
      notifyListeners();
      
      return _firstScreenContent!;
    } catch (e) {
      debugPrint('获取首屏内容失败: $e');
      return '无法加载首屏内容';
    }
  }
  
  /// 快速分页算法 - 仅计算第一页内容
  List<String> _getPageLines(List<String> lines, Size size, TextStyle style) {
    final page = <String>[];
    double height = 0;
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final tp = TextPainter(
        text: TextSpan(text: line, style: style),
        maxLines: null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 32);
      
      // 检查是否会超出页面高度
      if (height + tp.height > size.height - 32 && page.isNotEmpty) {
        break; // 已经填满一页，停止添加内容
      }
      
      page.add(line);
      height += tp.height;
    }
    
    return page;
  }
  
  /// 预加载相邻页面以提高浏览体验
  Future<void> preloadAdjacentPages(int currentIndex) async {
    if (_paginationEngine != null) {
      await _paginationEngine!.preloadAdjacentPages(currentIndex);
    }
  }
  
  /// 获取当前总页数
  int getTotalPages() {
    return _estimatedTotalPages ?? 0;
  }
  
  /// 检查页面索引是否有效
  bool isValidPageIndex(int index) {
    // 稍微放宽条件，允许访问接近估算总数的页面
    return index >= 0 && index <= (_estimatedTotalPages ?? 0) + 10;
  }
  
  /// 检查是否已有缓存的页面数据
  bool get hasCachedData {
    return _estimatedTotalPages != null && _estimatedTotalPages! > 0;
  }
  
  /// 检查分页引擎是否已基于章节锚点重建完成
  /// 这个getter用于确保恢复逻辑在正确的时机执行
  bool get paginationRebuiltWithChapters => _paginationRebuiltWithChapters;
  
  /// 清理页面起始行号缓存，通常在章节跳转后调用以避免缓存污染
  void clearPageStartLineCache() {
    _pageStartLineCache.clear();
  }
  
  /// 清理所有与分页相关的缓存，在跳转锚点时调用
  void clearAllPaginationCache() {
    clearPageStartLineCache();
    _paginationEngine?.clearCache();
  }
  
  /// 只清理页面内容缓存，保留页面边界缓存（用于章节跳转优化）
  void clearPageContentCacheOnly() {
    _paginationEngine?.clearPageContentCacheOnly();
  }
  
  /// 根据行号估算页码（用于预加载优化）
  int estimatePageFromLineIndex(int lineIndex) {
    if (_lines == null || _lines!.isEmpty || lineIndex < 0) {
      return 0;
    }
    
    if (lineIndex >= _lines!.length) {
      return (_estimatedTotalPages ?? 0) - 1;
    }
    
    // 使用平均行数估算
    final avgLinesPerPage = _estimateAverageLinesPerPage();
    if (avgLinesPerPage > 0) {
      return (lineIndex / avgLinesPerPage).floor();
    }
    
    return 0;
  }
  
  /// 后台解析章节信息的辅助函数
  static List<ChapterInfo> _parseChaptersInBackground(String content) {
    final chapters = <ChapterInfo>[];
    final lines = LineSplitter().convert(content);
    
    // 章节标题正则表达式，支持中英文数字，更宽松的匹配
    final chapterRegex = RegExp(r'^\s*第(\d+|[零一二三四五六七八九十百千万]+)章\s+(.+)', caseSensitive: false);
    
    debugPrint('开始解析章节，共${lines.length}行');
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final match = chapterRegex.firstMatch(line);
      if (match != null) {
        final title = match.group(0)!.trim();
        chapters.add(ChapterInfo(title: title, lineIndex: i));
        debugPrint('找到章节: $title, 行号: $i');
      }
    }
    
    debugPrint('章节解析完成，共找到${chapters.length}章');
    return chapters;
  }

  /// 解析章节信息，支持中英文数字格式，在后台线程执行
  Future<void> parseChapters() async {
    if (_chaptersLoaded) return;
    
    try {
      _chapters = [];
      
      // 读取文件内容
      final content = await utf8File.readAsString();
      
      // 使用compute在后台线程解析章节
      final chapters = await compute(_parseChaptersInBackground, content);
      
      // 在主线程更新UI相关状态
      _chapters = chapters;
      _chaptersLoaded = true;

      // 如果内容和分页信息已加载完成，则基于章节锚点重建分页引擎，实现「章节标题起页」
      if (_fullContentLoaded && _lines != null && _lastStyle != null && _lastSize != null) {
        try {
          // 章节行号集合，用作强制起页锚点
          final anchorLines = _chapters!
              .map((c) => c.lineIndex)
              .where((idx) => idx >= 0 && idx < _lines!.length)
              .toSet();

          if (anchorLines.isNotEmpty) {
            // 重建分页引擎（带章节锚点）
            _paginationEngine = OptimizedPaginationEngine(
              lines: _lines!,
              style: _lastStyle!,
              size: _lastSize!,
              forcedPageStartLineIndices: anchorLines,
            );

            // 章节锚点引入后，页码映射会变化，需要清理相关缓存并重新估算总页数
            clearPageStartLineCache();
            _estimatedTotalPages = _paginationEngine!.estimateTotalPages();
            
            // 标记分页引擎已基于章节锚点重建完成
            _paginationRebuiltWithChapters = true;
            
            debugPrint('分页引擎已基于章节锚点重建完成，共${anchorLines.length}个章节锚点');
          } else {
            // 如果没有章节，也标记为完成（使用普通分页）
            _paginationRebuiltWithChapters = true;
          }
        } catch (e) {
          debugPrint('基于章节锚点重建分页引擎失败: $e');
          // 即使失败，也标记为完成，避免无限等待
          _paginationRebuiltWithChapters = true;
        }
      }
      
      notifyListeners(); // 通知监听器章节解析完成
    } catch (e) {
      debugPrint('解析章节失败: $e');
    }
  }
  
  /// 根据章节索引获取对应的行号
  int getLineIndexByChapterIndex(int chapterIndex) {
    if (_chapters != null && chapterIndex >= 0 && chapterIndex < _chapters!.length) {
      return _chapters![chapterIndex].lineIndex;
    }
    return 0;
  }
  
  /// 根据行号获取对应的章节索引
  int getChapterIndexByLineIndex(int lineIndex) {
    if (_chapters == null || _chapters!.isEmpty) return 0;
    
    for (int i = 0; i < _chapters!.length - 1; i++) {
      if (lineIndex >= _chapters![i].lineIndex && lineIndex < _chapters![i + 1].lineIndex) {
        return i;
      }
    }
    
    return _chapters!.length - 1;
  }
  
  /// 根据章节索引获取对应的页码（精确版本）
  /// 说明：
  /// - 直接基于行号和分页规则向前扫描，找到该行所在的页
  /// - 不依赖估算总页数，也不依赖页码范围的二分查找，避免大跨度跳转错乱
  Future<int> getPageIndexByChapterIndex(int chapterIndex) async {
    if (_chapters == null || chapterIndex < 0 || chapterIndex >= _chapters!.length) {
      return 0;
    }

    final targetLineIndex = _chapters![chapterIndex].lineIndex;

    // 如果分页引擎或行数据不存在，返回0
    if (_paginationEngine == null || _lines == null) {
      return 0;
    }

    // 确保目标行号在有效范围内
    if (targetLineIndex < 0) {
      return 0;
    }
    if (targetLineIndex >= _lines!.length) {
      // 超出范围时，尽量返回最后一页
      return (_estimatedTotalPages != null && _estimatedTotalPages! > 0)
          ? _estimatedTotalPages! - 1
          : 0;
    }

    // 交给分页引擎按行号精确查找所在页码
    return await _paginationEngine!.findPageIndexByLineIndex(targetLineIndex);
  }
  
  /// 页面边界缓存，用于存储已计算的页面起始行号
  final Map<int, int> _pageStartLineCache = {};
  
  /// 根据页码获取起始行号（异步版本）
  /// 改进版本：从已知的最近页面边界开始计算，避免递归过深
  Future<int> getStartLineIndexByPageIndexAsync(int pageIndex) async {
    if (_paginationEngine == null || _lines == null) {
      return 0;
    }
    
    // 检查缓存中是否有该页面的起始行号
    if (_pageStartLineCache.containsKey(pageIndex)) {
      return _pageStartLineCache[pageIndex]!;
    }
    
    // 如果是第一页，起始行号就是0
    if (pageIndex == 0) {
      _pageStartLineCache[0] = 0;
      return 0;
    }
    
    try {
      // 策略1：查找已知的最近页面边界，从那里开始计算
      int nearestKnownPage = -1;
      int nearestKnownStartLine = 0;
      
      // 向前查找已知的页面边界
      for (int i = pageIndex - 1; i >= 0; i--) {
        if (_pageStartLineCache.containsKey(i)) {
          nearestKnownPage = i;
          nearestKnownStartLine = _pageStartLineCache[i]!;
          break;
        }
      }
      
      // 如果找到了已知的页面边界，从那里开始逐步计算
      if (nearestKnownPage >= 0) {
        int currentPage = nearestKnownPage + 1;
        int currentStartLine = nearestKnownStartLine;
        
        // 从已知页面开始，逐步计算到目标页面
        while (currentPage <= pageIndex) {
          // 获取前一页的内容来确定当前页的起始行号
          final previousPageContent = await _paginationEngine!.getPageContent(currentPage - 1);
          if (previousPageContent.isEmpty) {
            // 如果前一页为空，说明已经超出范围，使用估算
            break;
          }
          
          // 当前页的起始行号 = 前一页的起始行号 + 前一页的行数
          currentStartLine = currentStartLine + previousPageContent.length;
          
          // 缓存当前页的起始行号
          _pageStartLineCache[currentPage] = currentStartLine;
          
          // 如果已经到达目标页面，返回
          if (currentPage == pageIndex) {
            return currentStartLine;
          }
          
          currentPage++;
          
          // 防止无限循环，如果计算了太多页面，使用估算
          if (currentPage - nearestKnownPage > 100) {
            break;
          }
        }
        
        // 如果成功计算到目标页面，返回结果
        if (_pageStartLineCache.containsKey(pageIndex)) {
          return _pageStartLineCache[pageIndex]!;
        }
      }
      
      // 策略2：如果找不到已知边界，尝试从第0页开始计算（但限制深度）
      if (nearestKnownPage < 0 && pageIndex <= 50) {
        // 只对前50页使用递归计算
        final previousPageContent = await _paginationEngine!.getPageContent(pageIndex - 1);
        final previousStartLine = await getStartLineIndexByPageIndexAsync(pageIndex - 1);
        final estimatedStartLine = previousStartLine + previousPageContent.length;
        
        _pageStartLineCache[pageIndex] = estimatedStartLine;
        return estimatedStartLine;
      }
      
      // 策略3：使用分页引擎的页面边界信息（如果可用）
      // 检查分页引擎是否有该页面的边界信息
      final pageContent = await _paginationEngine!.getPageContent(pageIndex);
      if (pageContent.isNotEmpty) {
        // 如果能获取到页面内容，尝试通过前一页计算起始行号
        if (pageIndex > 0) {
          try {
            final prevStartLine = await getStartLineIndexByPageIndexAsync(pageIndex - 1);
            final prevPageContent = await _paginationEngine!.getPageContent(pageIndex - 1);
            final startLine = prevStartLine + prevPageContent.length;
            _pageStartLineCache[pageIndex] = startLine;
            return startLine;
          } catch (e) {
            // 如果失败，继续使用估算
          }
        }
      }
      
      // 策略4：使用估算值（最后的后备方案）
      // 基于已知的页面行数平均值来估算
      final estimatedLinesPerPage = _estimateAverageLinesPerPage();
      final estimatedStartLine = pageIndex * estimatedLinesPerPage;
      
      // 限制缓存大小
      if (_pageStartLineCache.length > 1000) {
        final keys = _pageStartLineCache.keys.toList()..sort();
        for (int i = 0; i < keys.length ~/ 2; i++) {
          _pageStartLineCache.remove(keys[i]);
        }
      }
      
      _pageStartLineCache[pageIndex] = estimatedStartLine;
      return estimatedStartLine;
    } catch (e) {
      debugPrint('获取页面起始行号失败: $e');
      // 最后的回退方案
      const averageLinesPerPage = 100;
      final safePageIndex = pageIndex < 0 ? 0 : pageIndex;
      final estimatedStartLine = safePageIndex * averageLinesPerPage;
      _pageStartLineCache[pageIndex] = estimatedStartLine;
      return estimatedStartLine;
    }
  }
  
  /// 估算平均每页的行数
  int _estimateAverageLinesPerPage() {
    if (_paginationEngine == null || _lines == null) {
      return 100; // 默认值
    }
    
    // 从缓存中计算已计算页面的平均行数
    final List<int> lineCounts = [];
    final sortedPages = _pageStartLineCache.keys.toList()..sort();
    
    for (int i = 0; i < sortedPages.length - 1; i++) {
      final page1 = sortedPages[i];
      final page2 = sortedPages[i + 1];
      final startLine1 = _pageStartLineCache[page1]!;
      final startLine2 = _pageStartLineCache[page2]!;
      lineCounts.add(startLine2 - startLine1);
    }
    
    if (lineCounts.isNotEmpty) {
      final average = lineCounts.reduce((a, b) => a + b) ~/ lineCounts.length;
      return average > 0 ? average : 100;
    }
    
    // 如果没有缓存数据，使用分页引擎的估算
    if (_paginationEngine != null) {
      final estimatedTotalPages = _paginationEngine!.estimateTotalPages();
      if (estimatedTotalPages > 0 && _lines!.isNotEmpty) {
        return (_lines!.length / estimatedTotalPages).ceil();
      }
    }
    
    return 100; // 默认值
  }
  
  /// 根据页码获取起始行号（同步版本，用于不支持异步的场景）
  int getStartLineIndexByPageIndex(int pageIndex) {
    if (_pageStartLineCache.containsKey(pageIndex)) {
      return _pageStartLineCache[pageIndex]!;
    }
    
    // 简单估算
    const averageLinesPerPage = 100;
    final estimatedStartLine = pageIndex * averageLinesPerPage;
    _pageStartLineCache[pageIndex] = estimatedStartLine;
    return estimatedStartLine;
  }
}
