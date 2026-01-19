import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'pagination_engine.dart';
import 'txt_segment_index.dart';
import 'txt_chapter_index.dart';

class PageRef {
  final int segmentIndex;
  final int pageInSegment;
  final int segmentStartOffset;
  final int pageStartOffset;

  const PageRef({
    required this.segmentIndex,
    required this.pageInSegment,
    required this.segmentStartOffset,
    required this.pageStartOffset,
  });
}

class ReaderController extends ChangeNotifier {
  final File utf8File;
  final String? novelTitle;

  List<List<String>> pages = [];

  List<String> _carryLines = [];
  List<int> _carryAbsOffsets = [];
  int _carrySegmentIndex = 0;
  int _carrySegmentStartOffset = 0;

  TxtSegmentIndex? _index;
  TxtChapterIndex? _chapterIndex;
  final List<PageRef> _pageRefs = [];

  int _loadedMaxSegmentIndex = -1;
  int _loadedMinSegmentIndex = 0;
  bool _loadingMore = false;
  int initialGlobalPage = 0;

  static final RegExp _chapterRegex =
      RegExp(r'^第([零一二三四五六七八九十百千万\d]+)(章|节|回|话)[\s:_]*(.*)$');

  ReaderController(this.utf8File, {this.novelTitle});

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

  Future<void> ensureChapterIndexLoaded() async {
    if (_chapterIndex != null) return;
    try {
      _chapterIndex = await TxtChapterIndexManager.loadOrBuild(utf8File);
    } catch (_) {}
  }

  int chapterIndexAtOffset(int byteOffset) {
    final idx = _chapterIndex;
    if (idx == null) return 0;
    return idx.chapterIndexAtOffset(byteOffset);
  }

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

  Future<int> jumpToByteOffset(
    int byteOffset,
    Size size,
    TextStyle style, {
    double paragraphSpacing = 0,
  }) async {
    await ensureChapterIndexLoaded();

    final segIndex = _segmentIndexAtOffset(byteOffset);
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
    notifyListeners();
    return initialGlobalPage;
  }

  Future<void> loadInitial(
    Size size,
    TextStyle style, {
    int startSegmentIndex = 0,
    int startPageInSegment = 0,
    int segmentCharCount = 5000,
    double paragraphSpacing = 0,
  }) async {
    pages = [];
    _pageRefs.clear();
    _carryLines = [];
    _carryAbsOffsets = [];
    _carrySegmentIndex = 0;
    _carrySegmentStartOffset = 0;
    _loadedMaxSegmentIndex = -1;
    _loadedMinSegmentIndex = 0;
    initialGlobalPage = 0;

    _index = await TxtSegmentIndexManager.loadOrBuild(
      utf8File,
      segmentCharCount: segmentCharCount,
    );

    unawaited(ensureChapterIndexLoaded());

    final idx = _index!;
    final safeSegment = startSegmentIndex.clamp(0, idx.segmentCount - 1);

    await _appendSegmentPages(safeSegment, size, style, paragraphSpacing: paragraphSpacing);
    _loadedMaxSegmentIndex = safeSegment;
    _loadedMinSegmentIndex = safeSegment;

    if (pages.isEmpty) {
      initialGlobalPage = 0;
    } else {
      initialGlobalPage = startPageInSegment.clamp(0, pages.length - 1);
    }
    notifyListeners();

    unawaited(ensureMoreIfNeeded(initialGlobalPage, size, style, paragraphSpacing: paragraphSpacing));
  }

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

  Future<void> _appendSegmentPages(
    int segmentIndex,
    Size size,
    TextStyle style, {
    double paragraphSpacing = 0,
  }) async {
    final idx = _index;
    if (idx == null) return;

    final start = idx.segmentStart(segmentIndex);
    final end = idx.segmentEnd(segmentIndex);
    final bytes = await _readBytesRange(utf8File, start, end);

    final lines = <String>[];
    final lineStartOffsets = <int>[];
    var currentLineStart = 0;
    final buf = <int>[];

    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b == 0x0A) {
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
    if (buf.isNotEmpty) {
      final text = utf8.decode(buf, allowMalformed: true).replaceAll('\r', '');
      lines.add(text);
      lineStartOffsets.add(currentLineStart);
    }

    final carryCount = _carryLines.length;
    final effectiveLines = carryCount == 0 ? lines : [..._carryLines, ...lines];

    final engine = PaginationEngine(effectiveLines, style, size, paragraphSpacing: paragraphSpacing);
    final segPages = engine.paginateWithLineIndexWhere(
      shouldStartNewPage: (line) => _chapterRegex.hasMatch(line.trim()),
    );

    if (segPages.isNotEmpty) {
      final last = segPages.last;
      final tp = TextPainter(
        text: TextSpan(text: last.lines.join('\n'), style: style),
        maxLines: null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);

      final isUnderfilled = tp.height < size.height * 0.75;
      final isChapterTitleOnly = last.lines.where((e) => e.trim().isNotEmpty).length == 1 &&
          _chapterRegex.hasMatch(last.lines.first.trim());

      if (isUnderfilled || isChapterTitleOnly) {
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
        _carryLines = [];
        _carryAbsOffsets = [];
      }
    }

    for (var i = 0; i < segPages.length; i++) {
      final p = segPages[i];
      pages.add(p.lines);

      final isFromCarry = p.startLineIndex < carryCount;
      final pageStartOffset = isFromCarry
          ? _carryAbsOffsets[p.startLineIndex]
          : start +
              (((p.startLineIndex - carryCount) >= 0 &&
                      (p.startLineIndex - carryCount) < lineStartOffsets.length)
                  ? lineStartOffsets[p.startLineIndex - carryCount]
                  : 0);

      _pageRefs.add(
        PageRef(
          segmentIndex: isFromCarry ? _carrySegmentIndex : segmentIndex,
          pageInSegment: i,
          segmentStartOffset: isFromCarry ? _carrySegmentStartOffset : start,
          pageStartOffset: pageStartOffset,
        ),
      );
    }
  }

  Future<int> _prependSegmentPages(
    int segmentIndex,
    Size size,
    TextStyle style, {
    double paragraphSpacing = 0,
  }) async {
    final idx = _index;
    if (idx == null) return 0;

    final start = idx.segmentStart(segmentIndex);
    final end = idx.segmentEnd(segmentIndex);
    final bytes = await _readBytesRange(utf8File, start, end);

    final lines = <String>[];
    final lineStartOffsets = <int>[];
    var currentLineStart = 0;
    final buf = <int>[];

    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b == 0x0A) {
        final text = utf8.decode(buf, allowMalformed: true).replaceAll('\r', '');
        lines.add(text);
        lineStartOffsets.add(currentLineStart);
        buf.clear();
        currentLineStart = i + 1;
      } else {
        buf.add(b);
      }
    }
    if (buf.isNotEmpty) {
      final text = utf8.decode(buf, allowMalformed: true).replaceAll('\r', '');
      lines.add(text);
      lineStartOffsets.add(currentLineStart);
    }

    final engine = PaginationEngine(lines, style, size, paragraphSpacing: paragraphSpacing);
    final segPages = engine.paginateWithLineIndexWhere(
      shouldStartNewPage: (line) => _chapterRegex.hasMatch(line.trim()),
    );
    if (segPages.isEmpty) return 0;

    final newPages = <List<String>>[];
    final newRefs = <PageRef>[];

    for (var i = 0; i < segPages.length; i++) {
      final p = segPages[i];
      newPages.add(p.lines);
      final lineOffsetInSeg =
          (p.startLineIndex >= 0 && p.startLineIndex < lineStartOffsets.length)
              ? lineStartOffsets[p.startLineIndex]
              : 0;
      final pageStartOffset = start + lineOffsetInSeg;
      newRefs.add(
        PageRef(
          segmentIndex: segmentIndex,
          pageInSegment: i,
          segmentStartOffset: start,
          pageStartOffset: pageStartOffset,
        ),
      );
    }

    pages.insertAll(0, newPages);
    _pageRefs.insertAll(0, newRefs);
    return newPages.length;
  }

  int _segmentIndexAtOffset(int byteOffset) {
    final idx = _index;
    if (idx == null || idx.segmentStartOffsets.isEmpty) return 0;

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

  int get totalChapters {
    final idx = _chapterIndex;
    if (idx == null) return 0;
    return idx.chapterCount;
  }

  List<String> get chapterTitles {
    final idx = _chapterIndex;
    if (idx == null) return [];
    return idx.chapterTitles;
  }
}
