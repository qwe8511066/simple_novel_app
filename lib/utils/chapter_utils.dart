import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../pages/reader/txt_chapter_index.dart';

/// 章节工具类
class ChapterUtils {
  /// 获取小说的章节列表
  static Future<List<Map<String, dynamic>>> getNovelChapters(
    String novelId,
  ) async {
    try {
      // 获取应用文档目录
      final dir = await getApplicationDocumentsDirectory();
      final novelDir = Directory('${dir.path}/novels');
      final file = File('${novelDir.path}/${novelId}');

      if (await file.exists()) {
        final idx = await TxtChapterIndexManager.loadOrBuild(file);
        return List.generate(idx.chapterTitles.length, (i) {
          return {
            'index': i,
            'title': idx.chapterTitles[i],
            'offset': idx.chapterStartOffsets[i],
          };
        });
      } else {
        return [];
      }
    } catch (e) {
      print('获取章节失败: $e');
      return [];
    }
  }

  /// 标准化章节标题，提取书名
  static Future<String> normalizeTitle(String input) async {
    final reg = RegExp(r'《([^》]+)》');
    final match = reg.firstMatch(input);
    if (match != null) {
      return match.group(1)!;
    }
    // 如果没有匹配到书名，返回原字符串
    return input;
  }
}
