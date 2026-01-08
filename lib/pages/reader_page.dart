import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/novel_provider.dart';
import '../models/novel.dart';

/// 阅读器页面
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.novelId, required this.initialChapterIndex});
  
  final String novelId;
  final int initialChapterIndex;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  String _content = '';
  bool _loading = true;
  Novel? _novel;
  int _currentChapterIndex = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.initialChapterIndex;
    _loadNovelContent();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 加载小说内容
  Future<void> _loadNovelContent() async {
    try {
      setState(() {
        _loading = true;
      });

      // 获取NovelProvider
      final novelProvider = Provider.of<NovelProvider>(context, listen: false);
      
      // 查找小说
      _novel = novelProvider.favoriteNovels.firstWhere(
        (n) => n.id == widget.novelId,
        orElse: () => throw Exception('小说不存在'),
      );

      // 获取应用文档目录
      final dir = await getApplicationDocumentsDirectory();
      final novelDir = Directory('${dir.path}/novels');
      final file = File('${novelDir.path}/${widget.novelId}');

      if (await file.exists()) {
        // 读取文件内容
        _content = await file.readAsString();
      } else {
        _content = '小说文件不存在';
      }

      // 恢复阅读进度
      if (_novel!.scrollProgress != null && _novel!.scrollProgress! > 0) {
        // 延迟执行滚动，确保页面已经构建完成
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent * _novel!.scrollProgress!,
          );
        });
      }
    } catch (e) {
      setState(() {
        _content = '加载失败: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  /// 保存阅读进度
  void _saveReadingProgress() {
    if (_scrollController.hasClients) {
      final maxScrollExtent = _scrollController.position.maxScrollExtent;
      final currentScrollPosition = _scrollController.position.pixels;
      double scrollProgress = 0.0;

      if (maxScrollExtent > 0) {
        scrollProgress = currentScrollPosition / maxScrollExtent;
      }

      // 更新阅读进度
      final novelProvider = Provider.of<NovelProvider>(context, listen: false);
      novelProvider.updateReadingProgress(
        widget.novelId,
        _currentChapterIndex,
        scrollProgress,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final novelProvider = Provider.of<NovelProvider>(context);
    final fontSize = novelProvider.fontSize;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_novel?.title ?? '阅读器'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    // 当用户停止滚动时保存阅读进度
                    if (notification is ScrollEndNotification) {
                      _saveReadingProgress();
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Text(
                      _content,
                      style: TextStyle(
                        fontSize: fontSize.toDouble(),
                        height: 1.8,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
