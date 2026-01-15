import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class TxtSegmentIndex {
  final String filePath;
  final int fileLength;
  final int fileModifiedMs;
  final int segmentCharCount;
  final List<int> segmentStartOffsets;

  const TxtSegmentIndex({
    required this.filePath,
    required this.fileLength,
    required this.fileModifiedMs,
    required this.segmentCharCount,
    required this.segmentStartOffsets,
  });

  factory TxtSegmentIndex.fromJson(Map<String, dynamic> json) {
    return TxtSegmentIndex(
      filePath: json['filePath'] as String,
      fileLength: json['fileLength'] as int,
      fileModifiedMs: json['fileModifiedMs'] as int,
      segmentCharCount: json['segmentCharCount'] as int,
      segmentStartOffsets:
          (json['segmentStartOffsets'] as List).cast<num>().map((e) => e.toInt()).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'fileLength': fileLength,
      'fileModifiedMs': fileModifiedMs,
      'segmentCharCount': segmentCharCount,
      'segmentStartOffsets': segmentStartOffsets,
    };
  }

  int get segmentCount => segmentStartOffsets.length;

  int segmentStart(int segmentIndex) => segmentStartOffsets[segmentIndex];

  int segmentEnd(int segmentIndex) {
    if (segmentIndex + 1 < segmentStartOffsets.length) {
      return segmentStartOffsets[segmentIndex + 1];
    }
    return fileLength;
  }
}

class TxtSegmentIndexManager {
  static Future<File> _indexFileFor(File txtFile) async {
    final dir = await getApplicationDocumentsDirectory();
    final indexDir = Directory(path.join(dir.path, 'novel_indexes'));
    if (!indexDir.existsSync()) {
      await indexDir.create(recursive: true);
    }
    return File(path.join(indexDir.path, '${path.basename(txtFile.path)}.idx.json'));
  }

  static Future<TxtSegmentIndex> loadOrBuild(
    File txtFile, {
    int segmentCharCount = 5000,
  }) async {
    final stat = await txtFile.stat();
    final idxFile = await _indexFileFor(txtFile);

    if (await idxFile.exists()) {
      try {
        final jsonMap = json.decode(await idxFile.readAsString()) as Map<String, dynamic>;
        final idx = TxtSegmentIndex.fromJson(jsonMap);
        if (idx.fileLength == stat.size &&
            idx.fileModifiedMs == stat.modified.millisecondsSinceEpoch &&
            idx.segmentCharCount == segmentCharCount &&
            idx.segmentStartOffsets.isNotEmpty) {
          return idx;
        }
      } catch (_) {}
    }

    final built = await compute(_buildIndexIsolate, {
      'filePath': txtFile.path,
      'fileLength': stat.size,
      'fileModifiedMs': stat.modified.millisecondsSinceEpoch,
      'segmentCharCount': segmentCharCount,
    });

    final idx = TxtSegmentIndex.fromJson(built);
    await idxFile.writeAsString(json.encode(idx.toJson()));
    return idx;
  }
}

Future<Map<String, dynamic>> _buildIndexIsolate(Map<String, dynamic> args) async {
  final filePath = args['filePath'] as String;
  final fileLength = args['fileLength'] as int;
  final fileModifiedMs = args['fileModifiedMs'] as int;
  final segmentCharCount = args['segmentCharCount'] as int;

  final file = File(filePath);
  final raf = await file.open(mode: FileMode.read);

  final offsets = <int>[0];
  var segmentChar = 0;

  try {
    const chunkSize = 64 * 1024;
    var globalPos = 0;
    while (globalPos < fileLength) {
      final toRead = (globalPos + chunkSize <= fileLength) ? chunkSize : (fileLength - globalPos);
      final chunk = await raf.read(toRead);
      if (chunk.isEmpty) break;

      var lineStartInChunk = 0;
      for (var i = 0; i < chunk.length; i++) {
        if (chunk[i] == 0x0A) {
          final lineBytes = chunk.sublist(lineStartInChunk, i + 1);
          final lineText = utf8.decode(lineBytes, allowMalformed: true);
          segmentChar += lineText.length;

          if (segmentChar >= segmentCharCount) {
            final nextOffset = globalPos + i + 1;
            if (nextOffset > offsets.last && nextOffset < fileLength) {
              offsets.add(nextOffset);
            }
            segmentChar = 0;
          }

          lineStartInChunk = i + 1;
        }
      }

      if (lineStartInChunk < chunk.length) {
        final tailBytes = chunk.sublist(lineStartInChunk);
        final tailText = utf8.decode(tailBytes, allowMalformed: true);
        segmentChar += tailText.length;
      }

      globalPos += chunk.length;
    }

    if (offsets.isEmpty) offsets.add(0);
    return {
      'filePath': filePath,
      'fileLength': fileLength,
      'fileModifiedMs': fileModifiedMs,
      'segmentCharCount': segmentCharCount,
      'segmentStartOffsets': offsets,
    };
  } finally {
    await raf.close();
  }
}
