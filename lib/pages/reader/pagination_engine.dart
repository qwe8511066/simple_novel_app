import 'package:flutter/material.dart';

class PaginationEngine {
  final List<String> lines;
  final TextStyle style;
  final Size size;

  PaginationEngine(this.lines, this.style, this.size);

  List<List<String>> paginate() {
    final pages = <List<String>>[];
    var page = <String>[];
    double height = 0;

    for (final line in lines) {
      final tp = TextPainter(
        text: TextSpan(text: line, style: style),
        maxLines: null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 32);

      if (height + tp.height > size.height - 32) {
        pages.add(page);
        page = [];
        height = 0;
      }

      page.add(line);
      height += tp.height;
    }

    if (page.isNotEmpty) pages.add(page);
    return pages;
  }
}
