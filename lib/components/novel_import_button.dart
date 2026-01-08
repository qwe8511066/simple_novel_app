import 'dart:convert';
import 'dart:io';

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
        backgroundColor: MaterialStateProperty.all(Theme.of(context).primaryColor),
        padding: MaterialStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
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
        
        try {
          // 先尝试UTF-8编码
          content = utf8.decode(bytes);
        } catch (e) {
          try {
            // 尝试GBK编码（中文常用编码）
            content = await CharsetConverter.decode("GBK", bytes);
          } catch (e) {
            try {
              // 尝试GB2312编码
              content = await CharsetConverter.decode("GB2312", bytes);
            } catch (e) {
              // 最后尝试Latin1编码
              content = latin1.decode(bytes);
            }
          }
        }

        // 保存到小说目录
        final targetFile = File('$novelDirPath/$fileName');
        await targetFile.writeAsString(content);

        // 创建Novel对象并添加到书架
        final novel = Novel(
          id: fileName,
          title: fileName.replaceAll('.txt', ''),
          author: '本地导入',
          coverUrl: '',
          description: '本地导入的小说',
          chapterCount: 1,
          category: '本地',
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
}
