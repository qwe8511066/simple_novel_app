// pagination_engine.dart
import 'package:flutter/widgets.dart';

class PaginationEngine {
  final TextStyle style;
  final Size pageSize;

  PaginationEngine({
    required this.style,
    required this.pageSize,
  });

  /// 返回：每一页的起始 offset
  List<int> paginate(String text) {
    final List<int> offsets = [0];

    final painter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    int start = 0;

    while (start < text.length) {
      painter.text = TextSpan(
        text: text.substring(start),
        style: style,
      );
      painter.layout(maxWidth: pageSize.width);

      final pos = painter.getPositionForOffset(
        Offset(0, pageSize.height),
      );

      final end = start + pos.offset;
      if (end <= start) break;

      offsets.add(end);
      start = end;
    }

    return offsets;
  }
}
