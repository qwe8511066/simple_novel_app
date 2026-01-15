import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class TxtChapterIndex {
  final String filePath;
  final int fileLength;
  final int fileModifiedMs;
  final List<int> chapterStartOffsets;
  final List<String> chapterTitles;

  const TxtChapterIndex({
    required this.filePath,
    required this.fileLength,
    required this.fileModifiedMs,
    required this.chapterStartOffsets,
    required this.chapterTitles,
  });

  factory TxtChapterIndex.fromJson(Map<String, dynamic> json) {
    return TxtChapterIndex(
      filePath: json['filePath'] as String,
      fileLength: json['fileLength'] as int,
      fileModifiedMs: json['fileModifiedMs'] as int,
      chapterStartOffsets:
          (json['chapterStartOffsets'] as List).cast<num>().map((e) => e.toInt()).toList(),
      chapterTitles: (json['chapterTitles'] as List).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'fileLength': fileLength,
      'fileModifiedMs': fileModifiedMs,
      'chapterStartOffsets': chapterStartOffsets,
      'chapterTitles': chapterTitles,
    };
  }

  int get chapterCount => chapterStartOffsets.length;

  int chapterIndexAtOffset(int byteOffset) {
    if (chapterStartOffsets.isEmpty) return 0;
    var lo = 0;
    var hi = chapterStartOffsets.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (chapterStartOffsets[mid] <= byteOffset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final idx = lo - 1;
    if (idx < 0) return 0;
    if (idx >= chapterStartOffsets.length) return chapterStartOffsets.length - 1;
    return idx;
  }

  String chapterTitleAt(int chapterIndex) {
    if (chapterTitles.isEmpty) return '';
    final i = chapterIndex.clamp(0, chapterTitles.length - 1);
    return chapterTitles[i];
  }
}

class TxtChapterIndexManager {
  static Future<File> _indexFileFor(File txtFile) async {
    final dir = await getApplicationDocumentsDirectory();
    final indexDir = Directory(path.join(dir.path, 'novel_indexes'));
    if (!indexDir.existsSync()) {
      await indexDir.create(recursive: true);
    }
    return File(path.join(indexDir.path, '${path.basename(txtFile.path)}.chap.json'));
  }

  static Future<TxtChapterIndex> loadOrBuild(File txtFile) async {
    final stat = await txtFile.stat();
    final idxFile = await _indexFileFor(txtFile);

    if (await idxFile.exists()) {
      try {
        final jsonMap = json.decode(await idxFile.readAsString()) as Map<String, dynamic>;
        final idx = TxtChapterIndex.fromJson(jsonMap);
        if (idx.fileLength == stat.size &&
            idx.fileModifiedMs == stat.modified.millisecondsSinceEpoch &&
            idx.chapterStartOffsets.isNotEmpty &&
            idx.chapterStartOffsets.length == idx.chapterTitles.length) {
          return idx;
        }
      } catch (_) {}
    }

    final built = await compute(_buildChapterIndexIsolate, {
      'filePath': txtFile.path,
      'fileLength': stat.size,
      'fileModifiedMs': stat.modified.millisecondsSinceEpoch,
    });

    final idx = TxtChapterIndex.fromJson(built);
    await idxFile.writeAsString(json.encode(idx.toJson()));
    return idx;
  }
}

Future<Map<String, dynamic>> _buildChapterIndexIsolate(Map<String, dynamic> args) async {
  final filePath = args['filePath'] as String;
  final fileLength = args['fileLength'] as int;
  final fileModifiedMs = args['fileModifiedMs'] as int;

  final file = File(filePath);
  final raf = await file.open(mode: FileMode.read);

  final offsets = <int>[];
  final titles = <String>[];

  final chapterRegex = RegExp(r'^第([零一二三四五六七八九十百千万\d]+)(章|节|回|话)[\s:_]*(.*)$');

  try {
    const chunkSize = 64 * 1024;
    var offset = 0;
    var lineStartOffset = 0;
    final lineBytes = <int>[];

    while (offset < fileLength) {
      final toRead = (offset + chunkSize <= fileLength) ? chunkSize : (fileLength - offset);
      final chunk = await raf.read(toRead);
      if (chunk.isEmpty) break;

      for (final b in chunk) {
        if (b == 0x0A) {
          final lineText = utf8.decode(lineBytes, allowMalformed: true).trim();
          if (lineText.isNotEmpty && chapterRegex.hasMatch(lineText)) {
            offsets.add(lineStartOffset);
            titles.add(lineText);
          }
          lineBytes.clear();
          offset += 1;
          lineStartOffset = offset;
        } else {
          lineBytes.add(b);
          offset += 1;
        }
      }
    }

    if (lineBytes.isNotEmpty) {
      final lineText = utf8.decode(lineBytes, allowMalformed: true).trim();
      if (lineText.isNotEmpty && chapterRegex.hasMatch(lineText)) {
        offsets.add(lineStartOffset);
        titles.add(lineText);
      }
    }

    if (offsets.isEmpty) {
      offsets.add(0);
      titles.add('第一章');
    }

    return {
      'filePath': filePath,
      'fileLength': fileLength,
      'fileModifiedMs': fileModifiedMs,
      'chapterStartOffsets': offsets,
      'chapterTitles': titles,
    };
  } finally {
    await raf.close();
  }
}
