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

  TxtSegmentIndex? _index;
  TxtChapterIndex? _chapterIndex;
  final List<PageRef> _pageRefs = [];

  int _loadedMaxSegmentIndex = -1;
  bool _loadingMore = false;
  int initialGlobalPage = 0;

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

  Future<void> loadInitial(
    Size size,
    TextStyle style, {
    int startSegmentIndex = 0,
    int startPageInSegment = 0,
    int segmentCharCount = 5000,
  }) async {
    pages = [];
    _pageRefs.clear();
    _loadedMaxSegmentIndex = -1;
    initialGlobalPage = 0;

    _index = await TxtSegmentIndexManager.loadOrBuild(
      utf8File,
      segmentCharCount: segmentCharCount,
    );

    unawaited(ensureChapterIndexLoaded());

    final idx = _index!;
    final safeSegment = startSegmentIndex.clamp(0, idx.segmentCount - 1);

    await _appendSegmentPages(safeSegment, size, style);
    _loadedMaxSegmentIndex = safeSegment;

    if (pages.isEmpty) {
      initialGlobalPage = 0;
    } else {
      initialGlobalPage = startPageInSegment.clamp(0, pages.length - 1);
    }
    notifyListeners();

    unawaited(ensureMoreIfNeeded(initialGlobalPage, size, style));
  }

  Future<void> ensureMoreIfNeeded(int currentGlobalPage, Size size, TextStyle style) async {
    final idx = _index;
    if (idx == null) return;
    if (_loadingMore) return;
    if (_loadedMaxSegmentIndex >= idx.segmentCount - 1) return;

    final remaining = pages.length - 1 - currentGlobalPage;
    if (remaining > 3) return;

    _loadingMore = true;
    try {
      final nextSeg = _loadedMaxSegmentIndex + 1;
      await _appendSegmentPages(nextSeg, size, style);
      _loadedMaxSegmentIndex = nextSeg;
      notifyListeners();
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _appendSegmentPages(int segmentIndex, Size size, TextStyle style) async {
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

    final engine = PaginationEngine(lines, style, size);
    final segPages = engine.paginateWithLineIndex();
    for (var i = 0; i < segPages.length; i++) {
      final p = segPages[i];
      pages.add(p.lines);
      final lineOffsetInSeg = (p.startLineIndex >= 0 && p.startLineIndex < lineStartOffsets.length)
          ? lineStartOffsets[p.startLineIndex]
          : 0;
      final pageStartOffset = start + lineOffsetInSeg;
      _pageRefs.add(PageRef(
        segmentIndex: segmentIndex,
        pageInSegment: i,
        segmentStartOffset: start,
        pageStartOffset: pageStartOffset,
      ));
    }
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

  static Future<Uint8List> _readBytesRange(File file, int start, int end) async {
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
}
