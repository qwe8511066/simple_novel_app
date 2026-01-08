import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/novel.dart';

/// 小说状态管理类
class NovelProvider with ChangeNotifier {
  List<Novel> _favoriteNovels = [];
  List<Novel> _recentNovels = [];
  String? _novelDirPath;
  bool _isDarkMode = false;
  double _fontSize = 14;
  Color _themeColor = Colors.blue; // 默认主题色

  /// 获取收藏的小说列表
  List<Novel> get favoriteNovels => _favoriteNovels;

  /// 获取最近阅读的小说列表
  List<Novel> get recentNovels => _recentNovels;
  
  /// 获取当前是否为夜间模式
  bool get isDarkMode => _isDarkMode;
  
  /// 获取当前字体大小
  double get fontSize => _fontSize;
  
  /// 获取当前主题色
  Color get themeColor => _themeColor;
  
  /// 初始化 - 加载本地小说
  Future<void> init() async {
    await _ensureNovelDirectory();
    await _loadNovelsFromLocal();
  }
  
  /// 确保小说目录存在
  Future<void> _ensureNovelDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final novelDir = Directory('${appDir.path}/novels');
    
    if (!novelDir.existsSync()) {
      await novelDir.create(recursive: true);
    }
    
    _novelDirPath = novelDir.path;
  }
  
  /// 从本地加载小说
  Future<void> _loadNovelsFromLocal() async {
    if (_novelDirPath == null) return;
    
    final dir = Directory(_novelDirPath!);
    if (!dir.existsSync()) return;
    
    // 读取目录中的所有.txt文件
    final files = dir.listSync()
        .where((entity) => entity is File && entity.path.endsWith('.txt'))
        .cast<File>();
    
    final loadedNovels = <Novel>[];
    
    for (final file in files) {
      try {
        // 使用basename函数获取文件名，这在所有平台上都有效
        final filename = path.basename(file.path);
        final id = filename;
        final title = filename.replaceAll('.txt', '');
        
        // 检查小说是否已存在
        if (!_favoriteNovels.any((n) => n.id == id)) {
          final novel = Novel(
            id: id,
            title: title,
            author: '本地导入',
            coverUrl: '',
            description: '本地导入的小说',
            chapterCount: 1,
            category: '本地',
            lastUpdateTime: file.lastModifiedSync().millisecondsSinceEpoch,
            lastChapterTitle: '第一章',
          );
          
          loadedNovels.add(novel);
        }
      } catch (e) {
        print('加载小说文件失败: $e');
      }
    }
    
    // 添加新发现的小说到收藏列表
    if (loadedNovels.isNotEmpty) {
      _favoriteNovels.addAll(loadedNovels);
      notifyListeners();
    }
  }

  /// 添加到收藏
  void addToFavorites(Novel novel) {
    if (!_favoriteNovels.any((n) => n.id == novel.id)) {
      _favoriteNovels.add(novel);
      notifyListeners();
    }
  }

  /// 从收藏中移除
  void removeFromFavorites(String novelId) {
    _favoriteNovels.removeWhere((novel) => novel.id == novelId);
    notifyListeners();
  }
  
  /// 切换夜间模式
  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }
  
  /// 设置夜间模式
  void setDarkMode(bool isDark) {
    _isDarkMode = isDark;
    notifyListeners();
  }
  
  /// 设置字体大小
  void setFontSize(double size) {
    _fontSize = size;
    notifyListeners();
  }
  
  /// 设置主题色
  void setThemeColor(Color color) {
    _themeColor = color;
    notifyListeners();
  }

  /// 切换收藏状态
  void toggleFavorite(Novel novel) {
    if (_favoriteNovels.any((n) => n.id == novel.id)) {
      removeFromFavorites(novel.id);
    } else {
      addToFavorites(novel);
    }
  }

  /// 检查小说是否已收藏
  bool isFavorite(String novelId) {
    return _favoriteNovels.any((novel) => novel.id == novelId);
  }

  /// 更新阅读进度
  void updateReadingProgress(String novelId, int chapter, double scrollProgress) {
    final index = _favoriteNovels.indexWhere((n) => n.id == novelId);
    if (index != -1) {
      final novel = _favoriteNovels[index];
      _favoriteNovels[index] = novel.copyWith(
        currentChapter: chapter,
        scrollProgress: scrollProgress,
      );
      notifyListeners();
    }

    // 更新最近阅读
    final recentIndex = _recentNovels.indexWhere((n) => n.id == novelId);
    if (recentIndex != -1) {
      _recentNovels.removeAt(recentIndex);
    }
    final novel = _favoriteNovels.firstWhere((n) => n.id == novelId, orElse: () {
      return Novel(
        id: '',
        title: '',
        author: '',
        coverUrl: '',
        description: '',
        chapterCount: 0,
        category: '',
        lastUpdateTime: 0,
        lastChapterTitle: '',
      );
    });
    if (novel.id.isNotEmpty) {
      _recentNovels.insert(0, novel);
      if (_recentNovels.length > 20) {
        _recentNovels.removeLast();
      }
      notifyListeners();
    }
  }

  /// 搜索小说
  List<Novel> searchNovels(String query, List<Novel> allNovels) {
    if (query.isEmpty) return [];
    final lowercaseQuery = query.toLowerCase();
    return allNovels
        .where((novel) =>
            novel.title.toLowerCase().contains(lowercaseQuery) ||
            novel.author.toLowerCase().contains(lowercaseQuery))
        .toList();
  }

  /// 根据分类获取小说
  List<Novel> getNovelsByCategory(String category, List<Novel> allNovels) {
    if (category == '全部') return allNovels;
    return allNovels.where((novel) => novel.category == category).toList();
  }

  /// 获取所有分类
  List<String> getAllCategories(List<Novel> allNovels) {
    final categories = allNovels.map((novel) => novel.category).toSet().toList();
    categories.insert(0, '全部');
    return categories;
  }
}
