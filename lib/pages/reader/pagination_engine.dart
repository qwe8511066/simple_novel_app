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
    double height = 0;

    var previousWasChapterTitle = false;

    int lineIndex = 0;
    while (lineIndex < lines.length) {
      final line = lines[lineIndex];

      if (shouldStartNewPage != null && shouldStartNewPage(line) && page.isNotEmpty) {
        pages.add(PaginatedPage(startLineIndex: pageStartLineIndex, lines: page));
        page = [];
        pageStartLineIndex = lineIndex;
        height = 0;
      }

      if (line.trim().isEmpty) {
        // Skip leading / repeated blank lines; paragraph spacing is handled explicitly.
        lineIndex++;
        continue;
      }

      final paragraphStartIndex = lineIndex;
      final paragraphLines = <String>[];
      while (lineIndex < lines.length && lines[lineIndex].trim().isNotEmpty) {
        paragraphLines.add(lines[lineIndex]);
        lineIndex++;
      }

      var hasSeparator = false;
      while (lineIndex < lines.length && lines[lineIndex].trim().isEmpty) {
        hasSeparator = true;
        lineIndex++;
      }

      final paragraphText = paragraphLines.join('\n');
      final tp = TextPainter(
        text: TextSpan(text: paragraphText, style: style),
        maxLines: null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);

      final isChapterTitleParagraph = shouldStartNewPage != null &&
          paragraphLines.isNotEmpty &&
          shouldStartNewPage(paragraphLines.first);

      final spacingBefore = page.isEmpty
          ? 0.0
          : (previousWasChapterTitle ? (paragraphSpacing * 0.5) : paragraphSpacing);
      if (height + spacingBefore + tp.height > size.height) {
        if (page.isNotEmpty) {
          pages.add(PaginatedPage(startLineIndex: pageStartLineIndex, lines: page));
          page = [];
          pageStartLineIndex = paragraphStartIndex;
          height = 0;
        }

        // Paragraph is too tall to fit in one page; fall back to line-based splitting.
        final startForSplit = paragraphStartIndex;
        for (var i = 0; i < paragraphLines.length; i++) {
          final l = paragraphLines[i];
          final lt = TextPainter(
            text: TextSpan(text: l, style: style),
            maxLines: null,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: size.width);

          if (height + lt.height > size.height) {
            if (page.isNotEmpty) {
              pages.add(PaginatedPage(startLineIndex: pageStartLineIndex, lines: page));
              page = [];
              pageStartLineIndex = startForSplit + i;
              height = 0;
            } else {
              pages.add(PaginatedPage(startLineIndex: startForSplit + i, lines: [l]));
              page = [];
              pageStartLineIndex = startForSplit + i + 1;
              height = 0;
              continue;
            }
          }

          page.add(l);
          height += lt.height;
        }

        if (hasSeparator && lineIndex < lines.length && !isChapterTitleParagraph) {
          page.add('');
        }
        previousWasChapterTitle = isChapterTitleParagraph;
        continue;
      }

      if (spacingBefore > 0) {
        height += spacingBefore;
      }
      page.addAll(paragraphLines);
      height += tp.height;

      // Do not preserve a blank separator right after a chapter title.
      if (hasSeparator && lineIndex < lines.length && !isChapterTitleParagraph) {
        page.add('');
      }
      previousWasChapterTitle = isChapterTitleParagraph;
    }

    if (page.isNotEmpty) {
      pages.add(PaginatedPage(startLineIndex: pageStartLineIndex, lines: page));
    }
    return pages;
  }
}
