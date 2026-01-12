/// 小说模型类
class Novel {
  final String id;
  final String title;
  final String author;
  final String coverUrl;
  final String description;
  final int chapterCount;
  final String category;
  final int lastUpdateTime;
  final String lastChapterTitle;
  final int? currentChapter;
  final double? scrollProgress;
  final int? currentPageIndex; // 当前页码
    
  // Legado风格的阅读进度坐标系统
  final int? durChapterIndex; // 当前章节索引
  final int? durChapterPos;   // 当前章节内的位置
  final int? durChapterPage;  // 当前章节内的页码
   
  Novel({
    required this.id,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.description,
    required this.chapterCount,
    required this.category,
    required this.lastUpdateTime,
    required this.lastChapterTitle,
    this.currentChapter,
    this.scrollProgress,
    this.currentPageIndex,
    this.durChapterIndex,
    this.durChapterPos,
    this.durChapterPage,
  });

  /// 从JSON创建Novel实例
  factory Novel.fromJson(Map<String, dynamic> json) {
    return Novel(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String,
      coverUrl: json['coverUrl'] as String,
      description: json['description'] as String,
      chapterCount: json['chapterCount'] as int,
      category: json['category'] as String,
      lastUpdateTime: json['lastUpdateTime'] as int,
      lastChapterTitle: json['lastChapterTitle'] as String,
      currentChapter: json['currentChapter'] as int?,
      scrollProgress: (json['scrollProgress'] as num?)?.toDouble(),
      currentPageIndex: json['currentPageIndex'] as int?,
      durChapterIndex: json['durChapterIndex'] as int?,
      durChapterPos: json['durChapterPos'] as int?,
      durChapterPage: json['durChapterPage'] as int?,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'coverUrl': coverUrl,
      'description': description,
      'chapterCount': chapterCount,
      'category': category,
      'lastUpdateTime': lastUpdateTime,
      'lastChapterTitle': lastChapterTitle,
      'currentChapter': currentChapter,
      'scrollProgress': scrollProgress,
      'currentPageIndex': currentPageIndex,
      'durChapterIndex': durChapterIndex,
      'durChapterPos': durChapterPos,
      'durChapterPage': durChapterPage,
    };
  }

  /// 复制并修改属性
  Novel copyWith({
    String? id,
    String? title,
    String? author,
    String? coverUrl,
    String? description,
    int? chapterCount,
    String? category,
    int? lastUpdateTime,
    String? lastChapterTitle,
    int? currentChapter,
    double? scrollProgress,
    int? currentPageIndex,
    int? durChapterIndex,
    int? durChapterPos,
    int? durChapterPage,
  }) {
    return Novel(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      coverUrl: coverUrl ?? this.coverUrl,
      description: description ?? this.description,
      chapterCount: chapterCount ?? this.chapterCount,
      category: category ?? this.category,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      lastChapterTitle: lastChapterTitle ?? this.lastChapterTitle,
      currentChapter: currentChapter ?? this.currentChapter,
      scrollProgress: scrollProgress ?? this.scrollProgress,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      durChapterIndex: durChapterIndex ?? this.durChapterIndex,
      durChapterPos: durChapterPos ?? this.durChapterPos,
      durChapterPage: durChapterPage ?? this.durChapterPage,
    );
  }
}
