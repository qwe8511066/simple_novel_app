import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/novel.dart';

/// 小说状态管理类
class NovelProvider with ChangeNotifier {
  List<Novel> _favoriteNovels = [];
  final List<Novel> _recentNovels = [];
  String? _novelDirPath;
  bool _isDarkMode = false;
  double _fontSize = 14;
  Color _themeColor = Colors.blue; // 默认主题色
  Color _bookshelfBackgroundColor = Colors.white; // 默认书架背景色
  String? _bookshelfBackgroundImage; // 书架背景图片路径

  /// 获取收藏的小说列表
  List<Novel> get favoriteNovels => _favoriteNovels;

  /// 根据ID获取小说
  Novel getNovelById(String id) {
    return _favoriteNovels.firstWhere(
      (n) => n.id == id,
      orElse: () => throw Exception('未找到ID为 $id 的小说'),
    );
  }

  /// 获取最近阅读的小说列表
  List<Novel> get recentNovels => _recentNovels;
  
  /// 获取当前是否为夜间模式
  bool get isDarkMode => _isDarkMode;
  
  /// 获取当前字体大小
  double get fontSize => _fontSize;
  
  /// 获取当前主题色
  Color get themeColor => _themeColor;
  
  /// 获取书架背景色
  Color get bookshelfBackgroundColor => _bookshelfBackgroundColor;
  
  /// 获取书架背景图片路径
  String? get bookshelfBackgroundImage => _bookshelfBackgroundImage;
  
  /// 初始化 - 加载本地小说和用户配置
  Future<void> init() async {
    await _ensureNovelDirectory();
    await _loadConfig();
    await _loadNovelsFromLocal();
  }
  
  /// 加载用户配置
  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 加载夜间模式
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    
    // 加载字体大小
    _fontSize = prefs.getDouble('fontSize') ?? 14;
    
    // 加载主题色
    final themeColorHex = prefs.getString('themeColor');
    if (themeColorHex != null) {
      _themeColor = Color(int.parse(themeColorHex, radix: 16));
    } else {
      _themeColor = Colors.blue;
    }
    
    // 加载书架背景色
    final bookshelfColorHex = prefs.getString('bookshelfBackgroundColor');
    if (bookshelfColorHex != null) {
      // 将十六进制颜色字符串转换为Color对象
      final hexColor = bookshelfColorHex.replaceAll('#', '');
      final int colorValue = int.parse(hexColor, radix: 16);
      final Color parsedColor = Color(colorValue + 0xFF000000);
      
      // 确保颜色不会太浅或太深
      final double lightness = HSLColor.fromColor(parsedColor).lightness;
      if (lightness < 0.2 || lightness > 0.8) {
        _bookshelfBackgroundColor = Colors.white; // 默认颜色
      } else {
        _bookshelfBackgroundColor = parsedColor;
      }
    } else {
      _bookshelfBackgroundColor = Colors.white;
    }
    
    // 加载书架背景图片路径
    _bookshelfBackgroundImage = prefs.getString('bookshelfBackgroundImage');

    // 加载小说收藏元数据(包含进度)
    final novelsJson = prefs.getString('favoriteNovelsMetadata');
    if (novelsJson != null) {
      try {
        final List<dynamic> list = json.decode(novelsJson);
        _favoriteNovels = list.map((item) => Novel.fromJson(item)).toList();
      } catch (e) {
        debugPrint('加载小说元数据失败: $e');
      }
    }
    
    notifyListeners();
  }
  
  /// 保存小说元数据
  Future<void> _saveNovelsMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = json.encode(_favoriteNovels.map((n) => n.toJson()).toList());
    await prefs.setString('favoriteNovelsMetadata', encoded);
  }
  
  /// 保存用户配置
  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 保存夜间模式
    await prefs.setBool('isDarkMode', _isDarkMode);
    
    // 保存字体大小
    await prefs.setDouble('fontSize', _fontSize);
    
    // 保存主题色
    await prefs.setString('themeColor', _themeColor.toARGB32().toRadixString(16));
    
    // 保存书架背景色
    await prefs.setString('bookshelfBackgroundColor', _bookshelfBackgroundColor.toARGB32().toRadixString(16));
    
    // 保存书架背景图片路径
    if (_bookshelfBackgroundImage != null) {
      await prefs.setString('bookshelfBackgroundImage', _bookshelfBackgroundImage!);
    } else {
      await prefs.remove('bookshelfBackgroundImage');
    }
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
    
    bool changed = false;
    
    // 1. 同步文件状态：如果文件被删除了，从收藏中移除
    final currentIds = files.map((f) => path.basename(f.path)).toSet();
    final initialCount = _favoriteNovels.length;
    _favoriteNovels.removeWhere((n) => n.category == '本地' && !currentIds.contains(n.id));
    if (_favoriteNovels.length != initialCount) changed = true;

    // 2. 发现新文件：如果有新文件，添加到列表
    for (final file in files) {
      try {
        final id = path.basename(file.path);
        final title = id.replaceAll('.txt', '');
        
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
          
          _favoriteNovels.add(novel);
          changed = true;
        }
      } catch (e) {
        debugPrint('加载小说文件失败: $e');
      }
    }
    
    if (changed) {
      _sortNovels();
      await _saveNovelsMetadata();
      notifyListeners();
    }
  }

  /// 添加到收藏
  void addToFavorites(Novel novel) {
    if (!_favoriteNovels.any((n) => n.id == novel.id)) {
      // 设置上传时间为当前时间
      final updatedNovel = novel.copyWith(
        lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
      );
      _favoriteNovels.add(updatedNovel);
      _sortNovels();
      notifyListeners();
    }
  }

  /// 从收藏中移除
  void removeFromFavorites(String novelId) {
    _favoriteNovels.removeWhere((novel) => novel.id == novelId);
    notifyListeners();
  }
  
  /// 切换夜间模式
  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置夜间模式
  Future<void> setDarkMode(bool isDark) async {
    _isDarkMode = isDark;
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置字体大小
  Future<void> setFontSize(double size) async {
    _fontSize = size;
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置主题色
  Future<void> setThemeColor(Color color) async {
    _themeColor = color;
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置书架背景色
  Future<void> setBookshelfBackgroundColor(Color color) async {
    _bookshelfBackgroundColor = color;
    _bookshelfBackgroundImage = null; // 清除背景图片
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置书架背景图片
  Future<void> setBookshelfBackgroundImage(String? imagePath) async {
    _bookshelfBackgroundImage = imagePath;
    notifyListeners();
    await _saveConfig();
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

  /// 对小说列表进行排序
  /// 最新上传的在前面，然后按最近的阅读时间排序
  void _sortNovels() {
    _favoriteNovels.sort((a, b) {
      // 按lastUpdateTime降序排序，最新的在前面
      return b.lastUpdateTime.compareTo(a.lastUpdateTime);
    });
  }

  /// 更新阅读进度
  void updateReadingProgress(String novelId, int chapter, double scrollProgress, {int? pageIndex, int? durChapterIndex, int? durChapterPos, int? durChapterPage}) {
    final index = _favoriteNovels.indexWhere((n) => n.id == novelId);
    if (index != -1) {
      final novel = _favoriteNovels[index];
      _favoriteNovels[index] = novel.copyWith(
        currentChapter: chapter,
        scrollProgress: scrollProgress,
        currentPageIndex: pageIndex,
        durChapterIndex: durChapterIndex,
        durChapterPos: durChapterPos,
        durChapterPage: durChapterPage,
        lastUpdateTime: DateTime.now().millisecondsSinceEpoch, // 更新阅读时间
      );
      _sortNovels();
      _saveNovelsMetadata(); // 持久化进度
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
