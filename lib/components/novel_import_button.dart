import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/novel.dart';
import '../providers/novel_provider.dart';

/// ===============================
/// 小说导入按钮组件
/// ===============================
class NovelImportButton extends StatelessWidget {
  const NovelImportButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () async {
        await _handleLocalFileImport(context);
      },
      child: const Text('导入小说', style: TextStyle(color: Colors.white)),
      style: ButtonStyle(
        // backgroundColor: MaterialStateProperty.all(Theme.of(context).primaryColor),
        // padding: MaterialStateProperty.all(
        //   const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        // ),
        shape: MaterialStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        textStyle: MaterialStateProperty.all(
          const TextStyle(fontSize: 14),
        ),
      ),
    );
  }

  /// ===============================
  /// 处理本地文件导入
  /// ===============================
  static Future<void> _handleLocalFileImport(BuildContext context) async {
    try {
      // 确保小说目录存在
      final novelDirPath = await _ensureNovelDirectory();
      if (novelDirPath == null) {
        throw Exception('无法获取小说目录');
      }

      // 打开文件选择器，允许选择多个txt文件
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        allowMultiple: true,
        dialogTitle: '选择要导入的小说文件',
        withData: false, // 不读取文件内容，提高性能
        withReadStream: false, // 不使用流
      );

      if (result == null || result.files.isEmpty) {
        return; // 用户取消选择
      }

      // 获取当前已存在的小说ID列表（用于去重）
      final novelProvider = Provider.of<NovelProvider>(context, listen: false);
      final existingNovelIds = novelProvider.favoriteNovels.map((n) => n.id).toSet();

      // 获取已存在的本地文件列表（用于去重）
      final dir = Directory(novelDirPath);
      final existingFiles = dir.listSync()
          .where((entity) => entity is File && entity.path.endsWith('.txt'))
          .cast<File>()
          .map((file) => path.basename(file.path))
          .toSet();

      // 导入选中的文件
      int successCount = 0;
      int skipCount = 0;

      for (final pickedFile in result.files) {
        final fileName = path.basename(pickedFile.path!);
        
        // 检查是否已存在（本地文件或书架中）
        if (existingFiles.contains(fileName) || existingNovelIds.contains(fileName)) {
          skipCount++;
          continue;
        }

        // 读取文件内容，支持多种编码
        final sourceFile = File(pickedFile.path!);
        final bytes = await sourceFile.readAsBytes();
        String content;
        
        // 智能检测编码
        content = await _decodeWithAutoDetect(bytes);

        // 保存到小说目录
        final targetFile = File('$novelDirPath/$fileName');
        await targetFile.writeAsString(content);

        // 创建Novel对象并添加到书架
        final novel = Novel(
          id: fileName,
              title: fileName.replaceAll('.txt', ''),
              coverUrl: '',
              chapterCount: 1,
              lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
              lastChapterTitle: '第一章',
        );

        novelProvider.addToFavorites(novel);
        successCount++;
      }

      // 显示导入结果
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '导入完成：成功 $successCount 本，跳过已存在 $skipCount 本',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('导入文件失败: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ===============================
  /// 确保小说目录存在
  /// ===============================
  static Future<String?> _ensureNovelDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('novel_dir_path');

    if (savedPath != null && Directory(savedPath).existsSync()) {
      return savedPath;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final novelDir = Directory('${appDir.path}/novels');

    if (!novelDir.existsSync()) {
      await novelDir.create(recursive: true);
    }

    await prefs.setString('novel_dir_path', novelDir.path);
    return novelDir.path;
  }

  /// ===============================
  /// 智能检测编码并解码
  /// ===============================
  static Future<String> _decodeWithAutoDetect(Uint8List bytes) async {
    if (bytes.isEmpty) return '';
    
    // 1. 检查BOM (Byte Order Mark)
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      // UTF-8 with BOM
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      // UTF-16 LE
      try {
        return await CharsetConverter.decode('utf-16le', bytes.sublist(2));
      } catch (_) {
        // fallback
      }
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      // UTF-16 BE
      try {
        return await CharsetConverter.decode('utf-16be', bytes.sublist(2));
      } catch (_) {
        // fallback
      }
    }
    
    // 2. 尝试严格UTF-8解码
    try {
      final result = utf8.decode(bytes, allowMalformed: false);
      // 检查是否包含常见乱码模式（GBK被UTF-8误读）
      if (!_containsGarbledPattern(result)) {
        return result;
      }
    } catch (_) {
      // UTF-8解码失败
    }
    
    // 3. 检测是否为GBK/GB18030编码
    if (_isLikelyGBK(bytes)) {
      try {
        final result = await CharsetConverter.decode('gbk', bytes);
        // 检查解码结果是否合理
        if (_isValidChineseText(result)) {
          return result;
        }
      } catch (_) {
        // GBK解码失败
      }
    }
    
    // 4. 尝试GB18030（更完整的中文编码）
    try {
      final result = await CharsetConverter.decode('gb18030', bytes);
      if (_isValidChineseText(result)) {
        return result;
      }
    } catch (_) {}
    
    // 5. 最后尝试GBK
    try {
      return await CharsetConverter.decode('gbk', bytes);
    } catch (_) {}
    
    // 6. 完全失败，使用容错模式UTF-8
    return utf8.decode(bytes, allowMalformed: true);
  }
  
  /// 检查文本是否包含常见的乱码模式
  static bool _containsGarbledPattern(String text) {
    // 常见的GBK被UTF-8误读产生的乱码字符
    final garbledPatterns = [
      'ä¸', 'å¤', 'æ', 'ç»', 'è¯', 'é¡', // 常见乱码前缀
      'ï¿½', // 替换字符
      'Ã¤', 'Ã¥', 'Ã¦', 'Ã§', 'Ã¨', 'Ã©', // 另一种乱码模式
    ];
    
    for (final pattern in garbledPatterns) {
      if (text.contains(pattern)) {
        return true;
      }
    }
    return false;
  }
  
  /// 检测字节序列是否可能是GBK编码
  static bool _isLikelyGBK(Uint8List bytes) {
    int gbkPatternCount = 0;
    int totalHighBytes = 0;
    
    for (int i = 0; i < bytes.length - 1; i++) {
      final b1 = bytes[i];
      final b2 = bytes[i + 1];
      
      if (b1 >= 0x80) {
        totalHighBytes++;
      }
      
      // GBK双字节范围：第一字节 0x81-0xFE，第二字节 0x40-0xFE
      if (b1 >= 0x81 && b1 <= 0xFE && b2 >= 0x40 && b2 <= 0xFE && b2 != 0x7F) {
        gbkPatternCount++;
        i++; // 跳过第二个字节
      }
    }
    
    // 如果GBK模式占高字节的大部分，可能是GBK
    return totalHighBytes > 0 && gbkPatternCount > totalHighBytes * 0.3;
  }
  
  /// 检查解码结果是否是有效的中文文本
  static bool _isValidChineseText(String text) {
    if (text.isEmpty) return false;
    
    // 检查是否包含有效的中文字符
    int chineseCount = 0;
    int garbledCount = 0;
    
    final sampleSize = min(1000, text.length);
    for (int i = 0; i < sampleSize; i++) {
      final code = text.codeUnitAt(i);
      // 中文字符范围
      if (code >= 0x4E00 && code <= 0x9FFF) {
        chineseCount++;
      }
      // 常见乱码字符
      if (code == 0xFFFD || (code >= 0x80 && code <= 0xFF)) {
        garbledCount++;
      }
    }
    
    // 如果中文字符超过乱码字符，认为是有效文本
    return chineseCount > garbledCount;
  }
}
