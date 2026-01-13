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
  
  // 快速加载相关变量
  String? _firstScreenContent;
  bool _firstScreenLoaded = false;
  bool _fullContentLoaded = false;
  
  // 章节信息
  List<ChapterInfo>? _chapters;
  bool _chaptersLoaded = false;

  ReaderController(this.utf8File, {this.novelTitle});

  bool get isLoading => _isLoading;
  
  bool get firstScreenLoaded => _firstScreenLoaded;
  bool get fullContentLoaded => _fullContentLoaded;
  bool get chaptersLoaded => _chaptersLoaded;
  String? get firstScreenContent => _firstScreenContent;
  List<ChapterInfo>? get chapters => _chapters;

  /// 流式加载文本内容，但不立即进行完整分页
  Future<void> load(Size size, TextStyle style) async {
    if (_isLoading) return; // 防止重复加载
    
    _isLoading = true;
    
    try {
      // 生成文件ID用于缓存
      final fileId = utf8File.path.hashCode.toString();
      final cache = PaginationCache();

      // 检查是否有缓存的完整分页结果
      final cachedPages = await cache.getCachedPages(fileId, utf8File);
      if (cachedPages != null && cachedPages.isNotEmpty) {
        // 如果有缓存的完整分页结果，使用传统方式加载
        // 这是为了向后兼容已有的缓存
        _isLoading = false;
        _estimatedTotalPages = cachedPages.length;
        // 仍然创建分页引擎，以便支持按需分页
        _lines = <String>[];
        await for (String line in utf8File.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
          _lines!.add(line);
          if (_lines!.length > 5000) break; // 只读取前5000行用于引擎初始化
        }
        _paginationEngine = OptimizedPaginationEngine(
          lines: _lines!,
          style: style,
          size: size,
        );
        _fullContentLoaded = true;
        notifyListeners();
        return;
      }

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

      // 创建按需分页引擎
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
    if (_paginationEngine != null && index >= 0 && index < (_estimatedTotalPages ?? 0)) {
      final pageContent = await _paginationEngine!.getPageContent(index);
      return pageContent.join('\n');
    }
    return '';
  }

  /// 获取总页数
  int get totalPages => _estimatedTotalPages ?? 0;

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
    return index >= 0 && index < (_estimatedTotalPages ?? 0);
  }
  
  /// 检查是否已有缓存的页面数据
  bool get hasCachedData {
    return _estimatedTotalPages != null && _estimatedTotalPages! > 0;
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
  
  /// 根据章节索引获取对应的页码
  Future<int> getPageIndexByChapterIndex(int chapterIndex) async {
    if (_chapters == null || chapterIndex < 0 || chapterIndex >= _chapters!.length) {
      return 0;
    }
    
    final targetLineIndex = _chapters![chapterIndex].lineIndex;
    
    // 如果分页引擎不存在，返回0
    if (_paginationEngine == null) {
      return 0;
    }
    
    // 计算总页数
    final totalPages = _paginationEngine!.estimateTotalPages();
    
    // 简单实现：从第一页开始加载页面内容，累积行数直到找到包含目标行号的页面
    int accumulatedLines = 0;
    for (int i = 0; i < totalPages; i++) {
      final pageContent = await _paginationEngine!.getPageContent(i);
      
      // 检查目标行号是否在当前页面
      if (targetLineIndex >= accumulatedLines && 
          targetLineIndex < accumulatedLines + pageContent.length) {
        return i;
      }
      
      // 累加当前页面的行数
      accumulatedLines += pageContent.length;
    }
    
    // 如果没有找到，返回最后一页
    return totalPages - 1;
  }
  
  /// 页面边界缓存，用于存储已计算的页面起始行号
  final Map<int, int> _pageStartLineCache = {};
  
  /// 根据页码获取起始行号（异步版本）
  Future<int> getStartLineIndexByPageIndexAsync(int pageIndex) async {
    if (_paginationEngine == null) {
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
      // 尝试获取该页面的内容，然后推断起始行号
      // 我们可以通过获取前一页的内容长度来计算起始行号
      final previousPageContent = await _paginationEngine!.getPageContent(pageIndex - 1);
      final previousStartLine = await getStartLineIndexByPageIndexAsync(pageIndex - 1);
      final estimatedStartLine = previousStartLine + previousPageContent.length;
      
      // 缓存估算结果
      _pageStartLineCache[pageIndex] = estimatedStartLine;
      return estimatedStartLine;
    } catch (e) {
      // 如果出现错误，回退到简单估算
      const averageLinesPerPage = 100;
      final estimatedStartLine = pageIndex * averageLinesPerPage;
      _pageStartLineCache[pageIndex] = estimatedStartLine;
      return estimatedStartLine;
    }
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
