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
  final double paragraphSpacing;

  PaginationEngine(
    this.lines,
    this.style,
    this.size, {
    this.paragraphSpacing = 0,
  });

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
        if (page.isNotEmpty) {
          pages.add(page);
          page = [];
          height = 0;
        } else {
          pages.add([line]);
          continue;
        }
      }

      page.add(line);
      height += tp.height;
    }

    if (page.isNotEmpty) pages.add(page);
    return pages;
  }

  List<PaginatedPage> paginateWithLineIndex() {
    return paginateWithLineIndexWhere();
  }

  List<PaginatedPage> paginateWithLineIndexWhere({
    bool Function(String line)? shouldStartNewPage,
  }) {
    final pages = <PaginatedPage>[];
    var page = <String>[];
    var pageStartLineIndex = 0;

    double _measureLinesHeight(List<String> lines) {
      final tp = TextPainter(
        text: TextSpan(text: lines.join('\n'), style: style),
        maxLines: null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      return tp.height;
    }

    void _flushPageIfNotEmpty() {
      if (page.isEmpty) return;
      pages.add(PaginatedPage(startLineIndex: pageStartLineIndex, lines: page));
      page = [];
    }

    int lineIndex = 0;
    while (lineIndex < lines.length) {
      var line = lines[lineIndex];
      final isChapterTitle =
          shouldStartNewPage != null && shouldStartNewPage(line.trim());

      if (isChapterTitle && page.isNotEmpty) {
        _flushPageIfNotEmpty();
        pageStartLineIndex = lineIndex;
      }

      while (true) {
        page.add(line);
        final h = _measureLinesHeight(page);

        if (h <= size.height) {
          break;
        }

        page.removeLast();

        if (page.isNotEmpty) {
          final baseHeight = _measureLinesHeight(page);
          final remaining = size.height - baseHeight;
          if (remaining > 0) {
            var lo = 1;
            var hi = line.length;
            var best = 0;
            while (lo <= hi) {
              final mid = (lo + hi) >> 1;
              final prefix = line.substring(0, mid);
              final testLines = [...page, prefix];
              final th = _measureLinesHeight(testLines);
              if (th <= size.height) {
                best = mid;
                lo = mid + 1;
              } else {
                hi = mid - 1;
              }
            }

            if (best > 0 && best < line.length) {
              final head = line.substring(0, best);
              final tail = line.substring(best);
              page.add(head);
              _flushPageIfNotEmpty();
              pageStartLineIndex = lineIndex;
              line = tail;
              continue;
            }
          }

          _flushPageIfNotEmpty();
          pageStartLineIndex = lineIndex;
          continue;
        }

        if (line.isNotEmpty) {
          var lo = 1;
          var hi = line.length;
          var best = 0;
          while (lo <= hi) {
            final mid = (lo + hi) >> 1;
            final prefix = line.substring(0, mid);
            final th = _measureLinesHeight([prefix]);
            if (th <= size.height) {
              best = mid;
              lo = mid + 1;
            } else {
              hi = mid - 1;
            }
          }
          if (best > 0 && best < line.length) {
            final head = line.substring(0, best);
            final tail = line.substring(best);
            page.add(head);
            _flushPageIfNotEmpty();
            pageStartLineIndex = lineIndex;
            line = tail;
            continue;
          }
        }

        page.add(line);
        _flushPageIfNotEmpty();
        pageStartLineIndex = lineIndex + 1;
        break;
      }

      lineIndex++;
    }

    if (page.isNotEmpty) {
      pages.add(PaginatedPage(startLineIndex: pageStartLineIndex, lines: page));
    }
    return pages;
  }
}
