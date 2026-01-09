import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'pagination_engine.dart';
import 'pagination_cache.dart';

class ReaderController extends ChangeNotifier {
  final File utf8File;
  final String? novelTitle;
  
  List<List<String>> pages = [];
  Size? _size;
  TextStyle? _style;
  bool _isLoading = false;

  ReaderController(this.utf8File, {this.novelTitle});

  bool get isLoading => _isLoading;

  /// 流式加载文本内容，避免一次性读取整个文件
  Future<void> load(Size size, TextStyle style) async {
    if (_isLoading) return; // 防止重复加载
    
    _isLoading = true;
    _size = size;
    _style = style;
    
    try {
      // 生成文件ID用于缓存
      final fileId = utf8File.path.hashCode.toString();
      final cache = PaginationCache();

      // 尝试从缓存加载
      final cachedPages = await cache.getCachedPages(fileId, utf8File);
      if (cachedPages != null) {
        pages = cachedPages;
        notifyListeners();
        return;
      }

      // 如果没有缓存，则进行流式读取和分页
      final lines = <String>[];
      
      // 逐行读取文件内容
      await for (String line in utf8File.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
        lines.add(line);
        
        // 每处理一定数量的行后让出控制权给UI线程，避免界面卡顿
        if (lines.length % 500 == 0) {
          await Future<void>.delayed(Duration.zero); // 让出控制权给UI线程
        }
      }

      // 使用分页引擎进行分页
      final engine = PaginationEngine(lines, style, size);
      pages = engine.paginate();
      
      // 保存到缓存
      await cache.savePagesToCache(fileId, utf8File, pages);
      
      notifyListeners();
    } finally {
      _isLoading = false;
    }
  }

  /// 获取指定页面内容
  String getPageContent(int index) {
    if (index >= 0 && index < pages.length) {
      return pages[index].join('\n');
    }
    return '';
  }

  /// 获取总页数
  int get totalPages => pages.length;
}
