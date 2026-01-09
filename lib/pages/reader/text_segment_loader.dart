// text_segment_loader.dart
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:charset_converter/charset_converter.dart';

class TextSegmentLoader {
  final File file;
  final int chunkSize;

  RandomAccessFile? _raf;
  int _offset = 0;
  bool _eof = false;
  List<int> _remainingBytes = [];
  String? _detectedEncoding; // 缓存检测到的编码

  TextSegmentLoader(this.file, {this.chunkSize = 64 * 1024});

  Future<void> open() async {
    _raf ??= await file.open();
    // 打开文件时立即检测编码
    await _detectFileEncoding();
  }

  bool get isEOF => _eof;

  /// 检测文件编码
  Future<void> _detectFileEncoding() async {
    if (_detectedEncoding != null) return;
    
    // 读取文件开头的数据来检测编码
    final fileLength = await file.length();
    final sampleSize = min(8192, fileLength);
    final raf = await file.open();
    final bytes = await raf.read(sampleSize);
    await raf.setPosition(0); // 重置位置
    await raf.close();
    
    // 1. 检查BOM
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      _detectedEncoding = 'utf-8-bom';
      return;
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      _detectedEncoding = 'utf-16le';
      return;
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      _detectedEncoding = 'utf-16be';
      return;
    }
    
    // 2. 尝试严格UTF-8解码
    try {
      utf8.decode(bytes, allowMalformed: false);
      // UTF-8解码成功，检查是否包含乱码模式
      final decoded = utf8.decode(bytes, allowMalformed: true);
      if (!_containsGarbledPattern(decoded)) {
        _detectedEncoding = 'utf-8';
        return;
      }
    } catch (_) {
      // UTF-8解码失败
    }
    
    // 3. 检测是否为GBK编码
    if (_isLikelyGBK(bytes)) {
      _detectedEncoding = 'gbk';
      return;
    }
    
    // 默认使用UTF-8
    _detectedEncoding = 'utf-8';
  }
  
  /// 检查是否包含常见乱码模式
  bool _containsGarbledPattern(String text) {
    // 常见的GBK被UTF-8误读产生的乱码字符
    final garbledPatterns = [
      'ä¸', 'å¤', 'æ', 'ç»', 'è¯', 'é¡',
      'ï¿½', 'Ã¤', 'Ã¥', 'Ã¦', 'Ã§', 'Ã¨', 'Ã©',
    ];
    
    for (final pattern in garbledPatterns) {
      if (text.contains(pattern)) {
        return true;
      }
    }
    return false;
  }
  
  /// 检测字节序列是否可能是GBK编码
  bool _isLikelyGBK(List<int> bytes) {
    int gbkPatternCount = 0;
    int totalHighBytes = 0;
    
    for (int i = 0; i < bytes.length - 1; i++) {
      final b1 = bytes[i];
      final b2 = bytes[i + 1];
      
      if (b1 >= 0x80) {
        totalHighBytes++;
      }
      
      // GBK双字节范围
      if (b1 >= 0x81 && b1 <= 0xFE && b2 >= 0x40 && b2 <= 0xFE && b2 != 0x7F) {
        gbkPatternCount++;
        i++;
      }
    }
    
    return totalHighBytes > 0 && gbkPatternCount > totalHighBytes * 0.3;
  }

  Future<String?> loadNext() async {
    if (_eof) return null;

    final bytes = await _raf!.read(chunkSize);
    if (bytes.isEmpty) {
      _eof = true;
      return _remainingBytes.isNotEmpty ? await _convertBytes(_remainingBytes) : null;
    }
    
    // 将剩余字节与新读取的字节合并
    final combinedBytes = [..._remainingBytes, ...bytes];
    _offset += bytes.length;
    
    // 根据编码类型处理字符边界
    List<int> validBytes;
    if (_detectedEncoding == 'gbk' || _detectedEncoding == 'gb2312' || _detectedEncoding == 'gb18030') {
      validBytes = _trimToValidGbkBoundary(combinedBytes);
    } else {
      validBytes = _trimToValidUtf8Boundary(combinedBytes);
    }
    
    // 保留未处理的字节
    _remainingBytes = combinedBytes.sublist(validBytes.length);
    
    return await _convertBytes(validBytes);
  }
  
  /// 修剪UTF-8字节到有效边界
  List<int> _trimToValidUtf8Boundary(List<int> bytes) {
    if (bytes.isEmpty) return bytes;
    
    int validLength = bytes.length;
    int attempts = 0;
    const maxAttempts = 6;
    
    while (validLength > 0 && attempts < maxAttempts) {
      final byte = bytes[validLength - 1];
      
      if (byte < 0x80) break;
      
      if ((byte & 0xC0) == 0x80) {
        validLength--;
        attempts++;
        continue;
      }
      
      int expectedLength = 0;
      if ((byte & 0xE0) == 0xC0) expectedLength = 2;
      else if ((byte & 0xF0) == 0xE0) expectedLength = 3;
      else if ((byte & 0xF8) == 0xF0) expectedLength = 4;
      
      int remainingBytes = bytes.length - validLength + 1;
      
      if (remainingBytes < expectedLength) {
        validLength--;
        attempts++;
      } else {
        break;
      }
    }
    
    return bytes.sublist(0, validLength);
  }
  
  /// 修剪GBK字节到有效边界
  List<int> _trimToValidGbkBoundary(List<int> bytes) {
    if (bytes.isEmpty) return bytes;
    
    int i = 0;
    int lastValidEnd = 0;
    
    while (i < bytes.length) {
      final b = bytes[i];
      
      if (b < 0x80) {
        i++;
        lastValidEnd = i;
      } else if (b >= 0x81 && b <= 0xFE) {
        if (i + 1 < bytes.length) {
          final b2 = bytes[i + 1];
          if ((b2 >= 0x40 && b2 <= 0x7E) || (b2 >= 0x80 && b2 <= 0xFE)) {
            i += 2;
            lastValidEnd = i;
          } else {
            i++;
            lastValidEnd = i;
          }
        } else {
          break;
        }
      } else {
        i++;
        lastValidEnd = i;
      }
    }
    
    return bytes.sublist(0, lastValidEnd);
  }

  /// 根据检测到的编码转换字节数组
  Future<String?> _convertBytes(List<int> bytes) async {
    if (bytes.isEmpty) return null;
    
    try {
      if (_detectedEncoding == 'utf-8' || _detectedEncoding == 'utf-8-bom') {
        // UTF-8编码
        try {
          return utf8.decode(bytes, allowMalformed: false);
        } catch (_) {
          return utf8.decode(bytes, allowMalformed: true);
        }
      } else if (_detectedEncoding == 'gbk' || _detectedEncoding == 'gb2312' || _detectedEncoding == 'gb18030') {
        // GBK/GB2312/GB18030编码
        try {
          return await CharsetConverter.decode('gbk', Uint8List.fromList(bytes));
        } catch (_) {
          // GBK失败，尝试UTF-8
          return utf8.decode(bytes, allowMalformed: true);
        }
      } else if (_detectedEncoding == 'utf-16le') {
        return await CharsetConverter.decode('utf-16le', Uint8List.fromList(bytes));
      } else if (_detectedEncoding == 'utf-16be') {
        return await CharsetConverter.decode('utf-16be', Uint8List.fromList(bytes));
      } else {
        // 默认UTF-8
        return utf8.decode(bytes, allowMalformed: true);
      }
    } catch (e) {
      // 所有解码失败，返回null
      return null;
    }
  }

  Future<void> close() async {
    await _raf?.close();
  }
}
