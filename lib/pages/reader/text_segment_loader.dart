import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:charset_converter/charset_converter.dart';

class TextSegmentLoader {
  final File sourceFile;
  late final File utf8CacheFile;

  TextSegmentLoader(this.sourceFile);

  /// 只做一次：转 UTF-8 + 按行
  Future<void> prepare() async {
    final dir = await Directory.systemTemp.createTemp('reader_cache');
    utf8CacheFile = File('${dir.path}/${sourceFile.uri.pathSegments.last}.utf8');

    if (await utf8CacheFile.exists()) return;

    final raf = await sourceFile.open();
    final out = utf8CacheFile.openWrite();

    final sample = await raf.read(4096);
    await raf.setPosition(0);

    final encoding = _detectEncoding(sample);

    final buffer = <int>[];
    while (true) {
      final chunk = await raf.read(64 * 1024);
      if (chunk.isEmpty) break;

      buffer.addAll(chunk);

      final text = await _decode(buffer, encoding);
      buffer.clear();

      out.write(text);
    }

    await out.close();
    await raf.close();
  }

  String _detectEncoding(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return 'utf-16le';
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return 'utf-16be';
    }
    try {
      utf8.decode(bytes, allowMalformed: false);
      return 'utf-8';
    } catch (_) {
      return 'gbk'; // ANSI 兜底
    }
  }

  Future<String> _decode(List<int> bytes, String enc) async {
    if (enc == 'utf-8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return CharsetConverter.decode(enc, Uint8List.fromList(bytes));
  }
}
