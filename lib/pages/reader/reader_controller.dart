import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'pagination_engine.dart';
import 'txt_segment_index.dart';

class PageRef {
  final int segmentIndex;
  final int pageInSegment;
  final int segmentStartOffset;

  const PageRef({
    required this.segmentIndex,
    required this.pageInSegment,
    required this.segmentStartOffset,
  });
}

class ReaderController extends ChangeNotifier {
  final File utf8File;
  final String? novelTitle;
  
  List<List<String>> pages = [];

  TxtSegmentIndex? _index;
  final List<PageRef> _pageRefs = [];

  int _loadedMaxSegmentIndex = -1;
  bool _loadingMore = false;
  int initialGlobalPage = 0;

  ReaderController(this.utf8File, {this.novelTitle});

  PageRef pageRefAt(int globalPageIndex) {
    if (globalPageIndex < 0 || globalPageIndex >= _pageRefs.length) {
      return const PageRef(segmentIndex: 0, pageInSegment: 0, segmentStartOffset: 0);
    }
    return _pageRefs[globalPageIndex];
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
    final segmentText = await _readUtf8Range(utf8File, start, end);
    final lines = segmentText
        .replaceAll('\r', '')
        .split('\n');

    final engine = PaginationEngine(lines, style, size);
    final segPages = engine.paginate();
    for (var i = 0; i < segPages.length; i++) {
      pages.add(segPages[i]);
      _pageRefs.add(PageRef(
        segmentIndex: segmentIndex,
        pageInSegment: i,
        segmentStartOffset: start,
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
}
