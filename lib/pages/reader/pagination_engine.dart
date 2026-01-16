import 'package:flutter/material.dart';

class PaginatedPage {
  final int startLineIndex;
  final List<String> lines;

  const PaginatedPage({
    required this.startLineIndex,
    required this.lines,
  });
}

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
      )..layout(maxWidth: size.width);

      if (height + tp.height > size.height) {
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

  List<PaginatedPage> paginateWithLineIndex() {
    final pages = <PaginatedPage>[];
    var page = <String>[];
    var pageStartLineIndex = 0;
    double height = 0;

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final tp = TextPainter(
        text: TextSpan(text: line, style: style),
        maxLines: null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);

      if (height + tp.height > size.height) {
        pages.add(PaginatedPage(startLineIndex: pageStartLineIndex, lines: page));
        page = [];
        pageStartLineIndex = lineIndex;
        height = 0;
      }

      page.add(line);
      height += tp.height;
    }

    if (page.isNotEmpty) {
      pages.add(PaginatedPage(startLineIndex: pageStartLineIndex, lines: page));
    }
    return pages;
  }
}
