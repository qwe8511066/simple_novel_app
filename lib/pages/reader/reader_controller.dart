import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'pagination_engine.dart';
import 'txt_segment_index.dart';
import 'txt_chapter_index.dart';

/// 页面引用类
/// 用于记录页面在文件中的位置信息
class PageRef {
  /// 段索引
  final int segmentIndex;
  /// 段内页面索引
  final int pageInSegment;
  /// 段起始偏移量
  final int segmentStartOffset;
  /// 页面起始偏移量
  final int pageStartOffset;

  const PageRef({
    required this.segmentIndex,
    required this.pageInSegment,
    required this.segmentStartOffset,
    required this.pageStartOffset,
  });
}

/// 阅读器控制器类
/// 负责管理页面加载、分页逻辑、章节索引等核心功能
class ReaderController extends ChangeNotifier {
  /// UTF8格式的小说文件
  final File utf8File;
  /// 小说标题
  final String? novelTitle;

  /// 所有页面的文本内容列表
  List<List<String>> pages = [];

  /// 用于跨段分页的行缓存
  List<String> _carryLines = [];
  /// 用于跨段分页的绝对偏移量缓存
  List<int> _carryAbsOffsets = [];
  /// 跨段分页的段索引
  int _carrySegmentIndex = 0;
  /// 跨段分页的段起始偏移量
  int _carrySegmentStartOffset = 0;

  /// 文本段索引
  TxtSegmentIndex? _index;
  /// 章节索引
  TxtChapterIndex? _chapterIndex;
  /// 页面引用列表
  final List<PageRef> _pageRefs = [];

  /// 已加载的最大段索引
  int _loadedMaxSegmentIndex = -1;
  /// 已加载的最小段索引
  int _loadedMinSegmentIndex = 0;
  /// 是否正在加载更多内容
  bool _loadingMore = false;
  /// 初始全局页面索引
  int initialGlobalPage = 0;

  /// 章节标题正则表达式
  /// 用于匹配类似"第1章"、"第100节"、"第两千回"等章节标题格式
  static final RegExp _chapterRegex =
      RegExp(r'^第([零一二三四五六七八九十百千万\d]+)(章|节|回|话)[\s:_]*(.*)$');

  /// 构造函数
  ReaderController(this.utf8File, {this.novelTitle});

  /// 获取指定全局页面索引的页面引用
  PageRef pageRefAt(int globalPageIndex) {
    if (globalPageIndex < 0 || globalPageIndex >= _pageRefs.length) {
      return const PageRef(
        segmentIndex: 0,
        pageInSegment: 0,
        segmentStartOffset: 0,
        pageStartOffset: 0,
      );
    }
    return _pageRefs[globalPageIndex];
  }

  /// 确保章节索引已加载
  Future<void> ensureChapterIndexLoaded() async {
    if (_chapterIndex != null) return;
    try {
      _chapterIndex = await TxtChapterIndexManager.loadOrBuild(utf8File);
    } catch (_) {}
  }

  /// 获取指定字节偏移量处的章节索引
  int chapterIndexAtOffset(int byteOffset) {
    final idx = _chapterIndex;
    if (idx == null) return 0;
    return idx.chapterIndexAtOffset(byteOffset);
  }

  /// 获取指定章节索引的章节标题
  String chapterTitleAtIndex(int chapterIndex) {
    final idx = _chapterIndex;
    if (idx == null) return '';
    return idx.chapterTitleAt(chapterIndex);
  }

  int chapterStartOffsetAt(int chapterIndex) {
    final idx = _chapterIndex;
    if (idx == null || idx.chapterStartOffsets.isEmpty) return 0;
    final i = chapterIndex.clamp(0, idx.chapterStartOffsets.length - 1);
    return idx.chapterStartOffsets[i];
  }

  /// 跳转到指定字节偏移量对应的页面
  Future<int> jumpToByteOffset(
    int byteOffset,
    Size size,
    TextStyle style, {
    double paragraphSpacing = 0,
  }) async {
    await ensureChapterIndexLoaded();

    // 确保分段索引已加载，否则_segmentIndexAtOffset会回退为0，导致恢复/跳转位置不准
    _index ??= await TxtSegmentIndexManager.loadOrBuild(utf8File);

    final segIndex = _segmentIndexAtOffset(byteOffset);
    assert(() {
      debugPrint('[ReaderJump] byteOffset=$byteOffset segIndex=$segIndex');
      return true;
    }());
    await loadInitial(
      size,
      style,
      startSegmentIndex: segIndex,
      startPageInSegment: 0,
      paragraphSpacing: paragraphSpacing,
    );

    var targetPage = 0;
    for (var i = 0; i < _pageRefs.length; i++) {
      if (_pageRefs[i].pageStartOffset <= byteOffset) {
        targetPage = i;
      } else {
        break;
      }
    }

    initialGlobalPage = targetPage.clamp(0, pages.isEmpty ? 0 : pages.length - 1);
    assert(() {
      debugPrint('[ReaderJump] targetPage=$initialGlobalPage pages=${pages.length}');
      return true;
    }());
    notifyListeners();
    return initialGlobalPage;
  }

  /// 加载初始页面
  Future<void> loadInitial(
    Size size,
    TextStyle style, {
    int startSegmentIndex = 0,
    int startPageInSegment = 0,
    int segmentCharCount = 5000,
    double paragraphSpacing = 0,
  }) async {
    // 重置所有状态
    pages = [];
    _pageRefs.clear();
    _carryLines = [];
    _carryAbsOffsets = [];
    _carrySegmentIndex = 0;
    _carrySegmentStartOffset = 0;
    _loadedMaxSegmentIndex = -1;
    _loadedMinSegmentIndex = 0;
    initialGlobalPage = 0;

    // 加载或构建文本段索引
    _index = await TxtSegmentIndexManager.loadOrBuild(
      utf8File,
      segmentCharCount: segmentCharCount,
    );

    // 异步加载章节索引
    unawaited(ensureChapterIndexLoaded());

    final idx = _index!;
    final safeSegment = startSegmentIndex.clamp(0, idx.segmentCount - 1);

    // 添加指定段的页面
    await _appendSegmentPages(safeSegment, size, style, paragraphSpacing: paragraphSpacing);
    _loadedMaxSegmentIndex = safeSegment;
    _loadedMinSegmentIndex = safeSegment;

    // 设置初始页面索引
    if (pages.isEmpty) {
      initialGlobalPage = 0;
    } else {
      initialGlobalPage = startPageInSegment.clamp(0, pages.length - 1);
    }
    notifyListeners();

    // 异步确保加载足够的内容
    unawaited(ensureMoreIfNeeded(initialGlobalPage, size, style, paragraphSpacing: paragraphSpacing));
  }

  /// 确保加载当前页面之前的内容（预加载）
  Future<int> ensurePreviousIfNeeded(
    int currentGlobalPage,
    Size size,
    TextStyle style, {
    double paragraphSpacing = 0,
  }) async {
    final idx = _index;
    if (idx == null) return 0;
    if (_loadingMore) return 0;
    if (_loadedMinSegmentIndex <= 0) return 0;

    // 如果当前页面距离起始页面还有3页以上，则不需要加载前面的内容
    if (currentGlobalPage > 3) return 0;

    _loadingMore = true;
    try {
      final prevSeg = _loadedMinSegmentIndex - 1;
      final added = await _prependSegmentPages(prevSeg, size, style, paragraphSpacing: paragraphSpacing);
      if (added > 0) {
        _loadedMinSegmentIndex = prevSeg;
        notifyListeners();
      }
      return added;
    } finally {
      _loadingMore = false;
    }
  }

  /// 确保加载当前页面之后的内容（预加载）
  Future<void> ensureMoreIfNeeded(
    int currentGlobalPage,
    Size size,
    TextStyle style, {
    double paragraphSpacing = 0,
  }) async {
    final idx = _index;
    if (idx == null) return;
    if (_loadingMore) return;
    if (_loadedMaxSegmentIndex >= idx.segmentCount - 1) return;

    // 如果当前页面距离最后一页还有3页以上，则不需要加载更多内容
    final remaining = pages.length - 1 - currentGlobalPage;
    if (remaining > 3) return;

    _loadingMore = true;
    try {
      final nextSeg = _loadedMaxSegmentIndex + 1;
      await _appendSegmentPages(nextSeg, size, style, paragraphSpacing: paragraphSpacing);
      _loadedMaxSegmentIndex = nextSeg;
      notifyListeners();
    } finally {
      _loadingMore = false;
    }
  }

  /// 追加指定段的页面到当前页面列表
  Future<void> _appendSegmentPages(
    int segmentIndex,
    Size size,
    TextStyle style, {
    double paragraphSpacing = 0,
  }) async {
    final idx = _index;
    if (idx == null) return;

    // 获取段的起始和结束偏移量
    final start = idx.segmentStart(segmentIndex);
    final end = idx.segmentEnd(segmentIndex);
    // 读取段的字节数据
    final bytes = await _readBytesRange(utf8File, start, end);

    // 将字节数据转换为行列表
    final lines = <String>[];
    final lineStartOffsets = <int>[];
    var currentLineStart = 0;
    final buf = <int>[];

    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b == 0x0A) { // 换行符
        final text = utf8
            .decode(buf, allowMalformed: true)
            .replaceAll('\r', '');
        lines.add(text);
        lineStartOffsets.add(currentLineStart);
        buf.clear();
        currentLineStart = i + 1;
      } else {
        buf.add(b);
      }
    }
    // 处理剩余的字节数据
    if (buf.isNotEmpty) {
      final text = utf8.decode(buf, allowMalformed: true).replaceAll('\r', '');
      lines.add(text);
      lineStartOffsets.add(currentLineStart);
    }

    // 处理跨段的行缓存
    final carryCount = _carryLines.length;
    final effectiveLines = carryCount == 0 ? lines : [..._carryLines, ...lines];

    // 使用分页引擎进行分页
    final engine = PaginationEngine(effectiveLines, style, size, paragraphSpacing: paragraphSpacing);
    final segPages = engine.paginateWithLineIndexWhere(
      shouldStartNewPage: (line) => _chapterRegex.hasMatch(line.trim()),
    );

    // 处理最后一页的情况
    if (segPages.isNotEmpty) {
      final last = segPages.last;
      final tp = TextPainter(
        text: TextSpan(text: last.lines.join('\n'), style: style),
        maxLines: null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);

      // 检查最后一页是否填充不足或只有章节标题
      final isUnderfilled = tp.height < size.height * 0.75;
      final isChapterTitleOnly = last.lines.where((e) => e.trim().isNotEmpty).length == 1 &&
          _chapterRegex.hasMatch(last.lines.first.trim());

      if (isUnderfilled || isChapterTitleOnly) {
        // 如果是，则将最后一页保留到下一段
        final absOffsets = <int>[];
        for (var j = 0; j < last.lines.length; j++) {
          final startLineIdx = last.startLineIndex + j;
          if (startLineIdx < carryCount) {
            absOffsets.add(_carryAbsOffsets[startLineIdx]);
          } else {
            final idxInSeg = startLineIdx - carryCount;
            final off = (idxInSeg >= 0 && idxInSeg < lineStartOffsets.length)
                ? lineStartOffsets[idxInSeg]
                : 0;
            absOffsets.add(start + off);
          }
        }

        _carryLines = List<String>.from(last.lines);
        _carryAbsOffsets = absOffsets;
        if (last.startLineIndex >= carryCount) {
          _carrySegmentIndex = segmentIndex;
          _carrySegmentStartOffset = start;
        }
        segPages.removeLast();
      } else {
        // 否则，清空行缓存
        _carryLines = [];
        _carryAbsOffsets = [];
      }
    }

    // 将分页结果添加到页面列表
    var keptPageInSegment = 0;
    for (var i = 0; i < segPages.length; i++) {
      final p = segPages[i];
      final isBlankPage = p.lines.every((e) => e.trim().isEmpty);
      if (isBlankPage) continue;

      pages.add(p.lines);

      // 计算页面的起始偏移量
      final isFromCarry = p.startLineIndex < carryCount;
      final pageStartOffset = isFromCarry
          ? _carryAbsOffsets[p.startLineIndex]
          : start +
              (((p.startLineIndex - carryCount) >= 0 &&
                      (p.startLineIndex - carryCount) < lineStartOffsets.length)
                  ? lineStartOffsets[p.startLineIndex - carryCount]
                  : 0);

      // 添加页面引用
      _pageRefs.add(
        PageRef(
          segmentIndex: isFromCarry ? _carrySegmentIndex : segmentIndex,
          pageInSegment: keptPageInSegment,
          segmentStartOffset: isFromCarry ? _carrySegmentStartOffset : start,
          pageStartOffset: pageStartOffset,
        ),
      );

      keptPageInSegment++;
    }
  }

  /// 在当前页面列表前面添加指定段的页面
  Future<int> _prependSegmentPages(
    int segmentIndex,
    Size size,
    TextStyle style, {
    double paragraphSpacing = 0,
  }) async {
    final idx = _index;
    if (idx == null) return 0;

    // 获取段的起始和结束偏移量
    final start = idx.segmentStart(segmentIndex);
    final end = idx.segmentEnd(segmentIndex);
    // 读取段的字节数据
    final bytes = await _readBytesRange(utf8File, start, end);

    // 将字节数据转换为行列表
    final lines = <String>[];
    final lineStartOffsets = <int>[];
    var currentLineStart = 0;
    final buf = <int>[];

    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b == 0x0A) { // 换行符
        final text = utf8.decode(buf, allowMalformed: true).replaceAll('\r', '');
        lines.add(text);
        lineStartOffsets.add(currentLineStart);
        buf.clear();
        currentLineStart = i + 1;
      } else {
        buf.add(b);
      }
    }
    // 处理剩余的字节数据
    if (buf.isNotEmpty) {
      final text = utf8.decode(buf, allowMalformed: true).replaceAll('\r', '');
      lines.add(text);
      lineStartOffsets.add(currentLineStart);
    }

    // 使用分页引擎进行分页
    final engine = PaginationEngine(lines, style, size, paragraphSpacing: paragraphSpacing);
    final segPages = engine.paginateWithLineIndexWhere(
      shouldStartNewPage: (line) => _chapterRegex.hasMatch(line.trim()),
    );
    if (segPages.isEmpty) return 0;

    // 准备新页面和引用列表
    final newPages = <List<String>>[];
    final newRefs = <PageRef>[];

    var keptPageInSegment = 0;
    for (var i = 0; i < segPages.length; i++) {
      final p = segPages[i];
      final isBlankPage = p.lines.every((e) => e.trim().isEmpty);
      if (isBlankPage) continue;

      newPages.add(p.lines);
      // 计算页面的起始偏移量
      final lineOffsetInSeg =
          (p.startLineIndex >= 0 && p.startLineIndex < lineStartOffsets.length)
              ? lineStartOffsets[p.startLineIndex]
              : 0;
      final pageStartOffset = start + lineOffsetInSeg;
      // 添加页面引用
      newRefs.add(
        PageRef(
          segmentIndex: segmentIndex,
          pageInSegment: keptPageInSegment,
          segmentStartOffset: start,
          pageStartOffset: pageStartOffset,
        ),
      );

      keptPageInSegment++;
    }

    // 在当前页面列表前面插入新页面
    pages.insertAll(0, newPages);
    _pageRefs.insertAll(0, newRefs);
    return newPages.length;
  }

  /// 获取指定字节偏移量对应的段索引
  int _segmentIndexAtOffset(int byteOffset) {
    final idx = _index;
    if (idx == null || idx.segmentStartOffsets.isEmpty) return 0;

    // 使用二分查找查找段索引
    var lo = 0;
    var hi = idx.segmentStartOffsets.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (idx.segmentStartOffsets[mid] <= byteOffset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final seg = (lo - 1).clamp(0, idx.segmentStartOffsets.length - 1);
    return seg;
  }

  /// 读取文件的UTF8字符串范围
  static Future<String> _readUtf8Range(File file, int start, int end) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(start);
      final length = (end - start).clamp(0, 1 << 31);
      final bytes = await raf.read(length);
      return utf8.decode(Uint8List.fromList(bytes), allowMalformed: true);
    } finally {
      await raf.close();
    }
  }

  /// 读取文件的字节范围
  static Future<Uint8List> _readBytesRange(
    File file,
    int start,
    int end,
  ) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(start);
      final length = (end - start).clamp(0, 1 << 31);
      final bytes = await raf.read(length);
      return Uint8List.fromList(bytes);
    } finally {
      await raf.close();
    }
  }

  /// 获取总章节数
  int get totalChapters {
    final idx = _chapterIndex;
    if (idx == null) return 0;
    return idx.chapterCount;
  }

  /// 获取所有章节标题
  List<String> get chapterTitles {
    final idx = _chapterIndex;
    if (idx == null) return [];
    return idx.chapterTitles;
  }
}
