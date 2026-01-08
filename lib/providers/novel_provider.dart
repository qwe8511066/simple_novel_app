import 'package:flutter/foundation.dart';
import '../models/novel.dart';

/// 小说状态管理类
class NovelProvider with ChangeNotifier {
  List<Novel> _favoriteNovels = [];
  List<Novel> _recentNovels = [];

  /// 获取收藏的小说列表
  List<Novel> get favoriteNovels => _favoriteNovels;

  /// 获取最近阅读的小说列表
  List<Novel> get recentNovels => _recentNovels;

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
