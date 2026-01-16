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

  double _fontSize = 18;
  double _readerFontSize = 21;
  FontWeight _fontWeight = FontWeight.normal; // 默认字体粗细
  Color _themeColor = Colors.blue; // 默认主题色
  Color _bookshelfBackgroundColor = Colors.white; // 默认书架背景色
  String? _bookshelfBackgroundImage; // 书架背景图片路径
  
  // 阅读界面设置
  Color _readerBackgroundColor = Colors.white; // 阅读界面背景色
  String? _readerBackgroundImage = 'assets/images/reader_backgrounds/10dec9361b40818e066b942ff9adb352.jpg'; // 默认阅读界面背景图片
  double _readerPaddingTop = 100; // 阅读界面顶部间距
  double _readerPaddingBottom = 40; // 阅读界面底部间距
  double _readerPaddingLeft = 20; // 阅读界面左侧间距
  double _readerPaddingRight = 20; // 阅读界面右侧间距
  double _letterSpacing = 0; // 字距
  double _lineSpacing = 2; // 行距
  double _paragraphSpacing = 16; // 段距
  String _fontFamily = 'FZZiZhuAYuanTiB'; // 默认字体
  String? _customFontPath; // 第三方字体文件路径
  
  // 界面设置
  String _pageTurnAnimation = '左右翻页'; // 翻页动画：左右翻页、上下翻页、仿真翻页
  bool _volumeKeyPageTurning = true; // 音量键翻页开关
  bool _hideStatusBar = true; // 隐藏状态栏开关
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

  /// 获取当前字体大小
  double get fontSize => _fontSize;
  
  /// 阅读界面字体大小
  double get readerFontSize => _readerFontSize;
  
  /// 字体粗细
  FontWeight get fontWeight => _fontWeight;
  
  /// 获取当前主题色
  Color get themeColor => _themeColor;
  
  /// 获取书架背景色
  Color get bookshelfBackgroundColor => _bookshelfBackgroundColor;
  
  /// 获取书架背景图片路径
  String? get bookshelfBackgroundImage => _bookshelfBackgroundImage;
  
  /// 阅读界面设置 getters
  Color get readerBackgroundColor => _readerBackgroundColor;
  String? get readerBackgroundImage => _readerBackgroundImage;
  double get readerPaddingTop => _readerPaddingTop;
  double get readerPaddingBottom => _readerPaddingBottom;
  double get readerPaddingLeft => _readerPaddingLeft;
  double get readerPaddingRight => _readerPaddingRight;
  double get letterSpacing => _letterSpacing;
  double get lineSpacing => _lineSpacing;
  double get paragraphSpacing => _paragraphSpacing;
  String get fontFamily => _fontFamily;
  String? get customFontPath => _customFontPath;
  
  // 界面设置 getters
  String get pageTurnAnimation => _pageTurnAnimation;
  bool get volumeKeyPageTurning => _volumeKeyPageTurning;
  bool get hideStatusBar => _hideStatusBar;
  
  /// 初始化 - 加载本地小说和用户配置
  Future<void> init() async {
    await _ensureNovelDirectory();
    await _loadConfig();
    await _loadNovelsFromLocal();
  }
  
  /// 加载用户配置
  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    

    // 加载字体大小和粗细
    _fontSize = prefs.getDouble('fontSize') ?? 18;
    _readerFontSize = prefs.getDouble('readerFontSize') ?? 21;
    _fontWeight = FontWeight.values[prefs.getInt('fontWeight') ?? FontWeight.normal.index];
    
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
    
    // 加载阅读界面背景色
    final readerColorHex = prefs.getString('readerBackgroundColor');
    if (readerColorHex != null) {
      _readerBackgroundColor = Color(int.parse(readerColorHex, radix: 16));
    } else {
      _readerBackgroundColor = Colors.white;
    }
    
    // 加载阅读界面背景图片路径
    _readerBackgroundImage = prefs.getString('readerBackgroundImage') ?? _readerBackgroundImage;
    
    // 加载阅读界面间距
    _readerPaddingTop = prefs.getDouble('readerPaddingTop') ?? _readerPaddingTop;
    _readerPaddingBottom = prefs.getDouble('readerPaddingBottom') ?? _readerPaddingBottom;
    _readerPaddingLeft = prefs.getDouble('readerPaddingLeft') ?? _readerPaddingLeft;
    _readerPaddingRight = prefs.getDouble('readerPaddingRight') ?? _readerPaddingRight;
    
    // 加载字体设置
    _letterSpacing = prefs.getDouble('letterSpacing') ?? _letterSpacing;
    _lineSpacing = prefs.getDouble('lineSpacing') ?? _lineSpacing;
    _paragraphSpacing = prefs.getDouble('paragraphSpacing') ?? _paragraphSpacing;
    _fontFamily = prefs.getString('fontFamily') ?? _fontFamily;
    _customFontPath = prefs.getString('customFontPath');
    
    // 加载界面设置
    _pageTurnAnimation = prefs.getString('pageTurnAnimation') ?? _pageTurnAnimation;
    _volumeKeyPageTurning = prefs.getBool('volumeKeyPageTurning') ?? _volumeKeyPageTurning;
    _hideStatusBar = prefs.getBool('hideStatusBar') ?? _hideStatusBar;

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
    

    // 保存字体大小和粗细
    await prefs.setDouble('fontSize', _fontSize);
    await prefs.setDouble('readerFontSize', _readerFontSize);
    await prefs.setInt('fontWeight', _fontWeight.index);
    
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
    
    // 保存阅读界面背景色
    await prefs.setString('readerBackgroundColor', _readerBackgroundColor.toARGB32().toRadixString(16));
    
    // 保存阅读界面背景图片路径
    if (_readerBackgroundImage != null) {
      await prefs.setString('readerBackgroundImage', _readerBackgroundImage!);
    } else {
      await prefs.remove('readerBackgroundImage');
    }
    
    // 保存阅读界面间距
    await prefs.setDouble('readerPaddingTop', _readerPaddingTop);
    await prefs.setDouble('readerPaddingBottom', _readerPaddingBottom);
    await prefs.setDouble('readerPaddingLeft', _readerPaddingLeft);
    await prefs.setDouble('readerPaddingRight', _readerPaddingRight);
    
    // 保存字体设置
    await prefs.setDouble('letterSpacing', _letterSpacing);
    await prefs.setDouble('lineSpacing', _lineSpacing);
    await prefs.setDouble('paragraphSpacing', _paragraphSpacing);
    await prefs.setString('fontFamily', _fontFamily);
    if (_customFontPath != null) {
      await prefs.setString('customFontPath', _customFontPath!);
    } else {
      await prefs.remove('customFontPath');
    }
    
    // 保存界面设置
    await prefs.setString('pageTurnAnimation', _pageTurnAnimation);
    await prefs.setBool('volumeKeyPageTurning', _volumeKeyPageTurning);
    await prefs.setBool('hideStatusBar', _hideStatusBar);
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
    _favoriteNovels.removeWhere((n) => currentIds.contains(n.id) == false);
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
            coverUrl: '',
            chapterCount: 1,
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
  


  /// 设置字体大小
  Future<void> setFontSize(double size) async {
    _fontSize = size;
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置阅读界面字体大小
  Future<void> setReaderFontSize(double size) async {
    _readerFontSize = size;
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置字体粗细
  Future<void> setFontWeight(FontWeight weight) async {
    _fontWeight = weight;
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
  
  /// 设置阅读界面背景色
  Future<void> setReaderBackgroundColor(Color color) async {
    _readerBackgroundColor = color;
    _readerBackgroundImage = null; // 清除背景图片
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置阅读界面背景图片
  Future<void> setReaderBackgroundImage(String? imagePath) async {
    _readerBackgroundImage = imagePath;
    notifyListeners();
    await _saveConfig();
  }
  
  /// 设置阅读界面间距
  Future<void> setReaderPadding({double? top, double? bottom, double? left, double? right}) async {
    if (top != null) _readerPaddingTop = top;
    if (bottom != null) _readerPaddingBottom = bottom;
    if (left != null) _readerPaddingLeft = left;
    if (right != null) _readerPaddingRight = right;
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置字距
  Future<void> setLetterSpacing(double spacing) async {
    _letterSpacing = spacing;
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置行距
  Future<void> setLineSpacing(double spacing) async {
    _lineSpacing = spacing;
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置段距
  Future<void> setParagraphSpacing(double spacing) async {
    _paragraphSpacing = spacing;
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置字体
  Future<void> setFontFamily(String fontFamily) async {
    // 检查是否是文件路径（第三方字体）
    if (fontFamily.endsWith('.ttf') || fontFamily.endsWith('.otf')) {
      _customFontPath = fontFamily;
      // 使用一个固定的字体族名，因为我们会通过FontLoader加载这个字体
      _fontFamily = 'CustomFont';
    } else {
      _fontFamily = fontFamily;
      _customFontPath = null;
    }
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置翻页动画
  Future<void> setPageTurnAnimation(String animation) async {
    _pageTurnAnimation = animation;
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置音量键翻页开关
  Future<void> setVolumeKeyPageTurning(bool enabled) async {
    _volumeKeyPageTurning = enabled;
    await _saveConfig();
    notifyListeners();
  }
  
  /// 设置隐藏状态栏开关
  Future<void> setHideStatusBar(bool enabled) async {
    _hideStatusBar = enabled;
    await _saveConfig();
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

  /// 对小说列表进行排序
  /// 最新上传的在前面，然后按最近的阅读时间排序
  void _sortNovels() {
    _favoriteNovels.sort((a, b) {
      // 按lastUpdateTime降序排序，最新的在前面
      return b.lastUpdateTime.compareTo(a.lastUpdateTime);
    });
  }
  
  /// 更新小说信息
  Future<void> updateNovel(Novel novel) async {
    final index = _favoriteNovels.indexWhere((n) => n.id == novel.id);
    if (index != -1) {
      _favoriteNovels[index] = novel;
      await _saveNovelsMetadata();
      notifyListeners();
    }
  }

  /// 仅更新阅读进度并持久化，不触发全局刷新
  Future<void> updateNovelProgress(Novel novel) async {
    final index = _favoriteNovels.indexWhere((n) => n.id == novel.id);
    if (index != -1) {
      _favoriteNovels[index] = novel;
      await _saveNovelsMetadata();
      notifyListeners();
    }
  }
  
  /// 重置阅读背景设置
  Future<void> resetBackgroundSettings() async {
    _readerBackgroundColor = Colors.white;
    _readerBackgroundImage = 'assets/images/reader_backgrounds/10dec9361b40818e066b942ff9adb352.jpg';
    await _saveConfig();
    notifyListeners();
  }
  
  /// 重置阅读间距设置
  Future<void> resetPaddingSettings() async {
    _readerPaddingTop = 100; // 与类定义的默认值一致
    _readerPaddingBottom = 40; // 与类定义的默认值一致
    _readerPaddingLeft = 20; // 与类定义的默认值一致
    _readerPaddingRight = 20; // 与类定义的默认值一致
    await _saveConfig();
    notifyListeners();
  }
  
  /// 重置阅读字体设置
  Future<void> resetFontSettings() async {
    _fontSize = 18;
    _readerFontSize = 21;
    _fontWeight = FontWeight.normal;
    _fontFamily = 'FZZiZhuAYuanTiB';
    _letterSpacing = 0;
    _lineSpacing = 2; // 与类定义的默认值一致
    _paragraphSpacing = 16;
    _customFontPath = null;
    await _saveConfig();
    notifyListeners();
  }
  
  /// 重置界面设置
  Future<void> resetInterfaceSettings() async {
    _pageTurnAnimation = '左右翻页';
    _volumeKeyPageTurning = true;
    _hideStatusBar = true;
    await _saveConfig();
    notifyListeners();
  }
}
