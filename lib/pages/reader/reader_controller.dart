import 'dart:io';
import 'dart:convert';
import 'dart:async';
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

  ReaderController(this.utf8File, {this.novelTitle});

  bool get isLoading => _isLoading;

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
        notifyListeners();
        return;
      }

      // 流式读取文件内容
      _lines = <String>[];
      await for (String line in utf8File.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
        _lines!.add(line);
        
        // 每处理一定数量的行后让出控制权给UI线程
        if (_lines!.length % 500 == 0) {
          await Future<void>.delayed(Duration.zero);
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

  /// 预加载相邻页面以提高浏览体验
  Future<void> preloadAdjacentPages(int currentIndex) async {
    if (_paginationEngine != null) {
      await _paginationEngine!.preloadAdjacentPages(currentIndex);
    }
  }
}
