import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/novel.dart';

/// 章节工具类
class ChapterUtils {
  /// 获取小说的章节列表
  static Future<List<Map<String, dynamic>>> getNovelChapters(String novelId) async {
    try {
      // 获取应用文档目录
      final dir = await getApplicationDocumentsDirectory();
      final novelDir = Directory('${dir.path}/novels');
      final file = File('${novelDir.path}/${novelId}');

      if (await file.exists()) {
        // 读取文件内容
        final content = await file.readAsString();
        
        // 解析章节
        final chapters = _parseChapters(content);
        return chapters;
      } else {
        return [];
      }
    } catch (e) {
      print('获取章节失败: $e');
      return [];
    }
  }

  /// 解析章节（使用正则表达式兼容多种章节格式）
  static List<Map<String, dynamic>> _parseChapters(String content) {
    final chapters = <Map<String, dynamic>>[];
    
    // 定义正则表达式，兼容多种章节格式：
    // 1. 第1章 胎穿
    // 2. 第0001章 论坛里的鬼故事
    // 3. 第三章
    // 4. 第1节 内容
    // 5. 第一章 （无标题）
    // 6. 第1章：胎穿 （冒号分隔）
    // 7. 第1章_胎穿 （下划线分隔）
    // 8. 第一回 内容
    // 9. 第一话 内容
    // 10. 第1章胎穿 （无分隔符）
    // 11. 第一章胎穿 （中文数字，无分隔符）
    // 支持阿拉伯数字（如1、0001）和中文数字（如一、二、三、十、十一等）
    // 支持不同章节单位（章、节、回、话）和可选分隔符（空格、冒号、下划线或无分隔符）
    final RegExp chapterRegex = RegExp(r'^第([零一二三四五六七八九十百千万\d]+)(章|节|回|话)[\s:_]*(.*)$');
    
    // 使用StringBuffer更高效地构建章节内容
    final StringBuffer currentChapter = StringBuffer();
    int chapterIndex = 0;
    
    // 使用LineSplitter更高效地分割行
    final lines = const LineSplitter().convert(content);
    
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) {
        // 保留空行，但如果是空章节则不添加
        if (currentChapter.isNotEmpty) {
          currentChapter.writeln();
        }
        continue;
      }
      
      // 检查是否是新章节
      if (chapterRegex.hasMatch(line)) {
        // 保存当前章节
        if (currentChapter.isNotEmpty) {
          final chapterContent = currentChapter.toString();
          final firstLine = chapterContent.split('\n').first;
          
          chapters.add({
            'index': chapterIndex++,
            'title': firstLine.isNotEmpty ? firstLine : '第${chapters.length + 1}章',
            'content': chapterContent,
          });
          
          // 清空当前章节内容
          currentChapter.clear();
        }
        
        // 开始新章节
        currentChapter.writeln(line);
      } else {
        // 添加到当前章节
        currentChapter.writeln(line);
      }
    }
    
    // 添加最后一章
    if (currentChapter.isNotEmpty) {
      final chapterContent = currentChapter.toString();
      final firstLine = chapterContent.split('\n').first;
      
      chapters.add({
        'index': chapterIndex,
        'title': firstLine.isNotEmpty ? firstLine : '第${chapters.length + 1}章',
        'content': chapterContent,
      });
    }
    
    return chapters;
  }

  /// 更新小说的章节数量
  static Future<void> updateNovelChapterCount(Novel novel, List<Map<String, dynamic>> chapters) async {
    try {
      // 获取应用文档目录
      final dir = await getApplicationDocumentsDirectory();
      final novelDir = Directory('${dir.path}/novels');
      final file = File('${novelDir.path}/${novel.id}');

      if (await file.exists()) {
        // 读取现有内容
        final content = await file.readAsString();
        final data = jsonDecode(content);
        
        // 更新章节数量
        data['chapterCount'] = chapters.length;
        
        // 写回文件
        await file.writeAsString(jsonEncode(data));
      }
    } catch (e) {
      print('更新章节数量失败: $e');
    }
  }
}
