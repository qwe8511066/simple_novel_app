/// 小说模型类
class Novel {
  final String id;
  final String title;
  final String coverUrl;
  final int chapterCount;
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
    required this.coverUrl,
    required this.chapterCount,
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
      coverUrl: json['coverUrl'] as String,
      chapterCount: json['chapterCount'] as int,
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
      'coverUrl': coverUrl,
      'chapterCount': chapterCount,
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
    String? coverUrl,
    int? chapterCount,
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
      coverUrl: coverUrl ?? this.coverUrl,
      chapterCount: chapterCount ?? this.chapterCount,
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
