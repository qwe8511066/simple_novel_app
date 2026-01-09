// reader_controller.dart
import 'package:flutter/material.dart';
import 'text_segment_loader.dart';
import 'pagination_engine.dart';

class ReaderController extends ChangeNotifier {
  final TextSegmentLoader loader;

  final StringBuffer _buffer = StringBuffer();
  List<int> _pageOffsets = [];

  bool contentReady = false;
  bool pageReady = false;

  ReaderController(this.loader);

  String get fullText => _buffer.toString();
  int get pageCount => _pageOffsets.length - 1;

  String pageText(int index) {
    if (index >= pageCount) return '';
    return fullText.substring(
      _pageOffsets[index],
      _pageOffsets[index + 1],
    );
  }

  Future<void> loadInitial() async {
    await loader.open();
    final first = await loader.loadNext();
    if (first != null) {
      _buffer.write(first);
      contentReady = true;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    final seg = await loader.loadNext();
    if (seg != null) {
      _buffer.write(seg);
    }
  }

  void repaginate(Size size, TextStyle style) {
    final engine = PaginationEngine(
      style: style,
      pageSize: size,
    );
    _pageOffsets = engine.paginate(fullText);
    pageReady = true;
    notifyListeners();
  }
}
