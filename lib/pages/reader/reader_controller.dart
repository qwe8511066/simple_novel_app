import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'pagination_engine.dart';
import 'pagination_cache.dart';
import 'on_demand_pagination.dart';

class ReaderController extends ChangeNotifier {
  final File utf8File;
  final String? novelTitle;
  
  // 按需分页引擎
  OnDemandPaginationEngine? _paginationEngine;
  List<String>? _lines;
  int? _estimatedTotalPages;
  bool _isLoading = false;
  
  // 快速加载相关变量
  String? _firstScreenContent;
  bool _firstScreenLoaded = false;
  bool _fullContentLoaded = false;

  ReaderController(this.utf8File, {this.novelTitle});

  bool get isLoading => _isLoading;
  
  bool get firstScreenLoaded => _firstScreenLoaded;
  bool get fullContentLoaded => _fullContentLoaded;
  String? get firstScreenContent => _firstScreenContent;

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
        _paginationEngine = OnDemandPaginationEngine(
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
            _paginationEngine = OnDemandPaginationEngine(
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
      _paginationEngine = OnDemandPaginationEngine(
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
      // 读取文件开头的字节（例如前10KB）
      final fileBytes = await utf8File.readAsBytes();
      final headerBytes = fileBytes.length > 10240 ? fileBytes.sublist(0, 10240) : fileBytes;
      
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
}
