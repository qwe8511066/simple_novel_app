import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/novel_provider.dart';
import '../models/novel.dart';
import '../utils/chapter_utils.dart';


/// 书架页面
class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  // 用于跟踪已经加载过章节的小说ID，避免重复加载
  final Set<String> _loadedNovelIds = {};
  
  // 用于跟踪和管理异步任务，确保页面销毁时能正确清理
  final List<Future<void>> _asyncTasks = [];
  
  @override
  void initState() {
    super.initState();
    
    // 延迟加载章节，确保UI先渲染完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNovelChapters();
    });
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // 当依赖项变化时，延迟检查是否需要加载章节
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNovelChapters();
    });
  }
  
  /// 为每个小说启动一个异步任务获取章节，限制并发数
  void _loadNovelChapters() {
    final novelProvider = Provider.of<NovelProvider>(context, listen: false);
    final favorites = novelProvider.favoriteNovels;
    
    // 过滤出需要加载章节的小说
    final novelsToLoad = favorites.where((novel) => !_loadedNovelIds.contains(novel.id)).toList();
    
    // 逐个处理小说，添加延迟避免阻塞
    for (int i = 0; i < novelsToLoad.length; i++) {
      final novel = novelsToLoad[i];
      _loadedNovelIds.add(novel.id);
      
      // 为每个小说添加递增的延迟，避免同时启动所有任务
      final task = Future.delayed(Duration(milliseconds: i * 500), () async {
        try {
          // 检查页面是否已经销毁
          if (!mounted) return;
          
          // 获取章节
          final chapters = await ChapterUtils.getNovelChapters(novel.id);
          
          // 再次检查页面是否已经销毁
          if (!mounted) return;
          
          // 更新小说的章节数量
          if (chapters.isNotEmpty && novel.chapterCount != chapters.length) {
            final updatedNovel = novel.copyWith(chapterCount: chapters.length);
            novelProvider.updateNovel(updatedNovel);
            
            // 更新本地存储
            await ChapterUtils.updateNovelChapterCount(updatedNovel, chapters);
          }
        } catch (e) {
          if (mounted) {
            print('处理小说章节失败 (${novel.title}): $e');
          }
        }
      });
      
      // 将任务添加到跟踪列表
      _asyncTasks.add(task);
      
      // 任务完成后从列表中移除
      task.whenComplete(() {
        _asyncTasks.remove(task);
      });
    }
  }
  
  @override
  void dispose() {
    // 清理资源，确保没有内存泄漏
    _asyncTasks.clear();
    super.dispose();
  }
  
  /// 构建默认封面，模拟Legado风格
  Widget _buildDefaultCover(String title) {
    // 处理标题显示
    String displayTitle = title.isNotEmpty ? title : '未知小说';
    
    // 截取标题的一部分用于显示，避免文字过长
    if (displayTitle.length > 8) {
      displayTitle = displayTitle.substring(0, 8) + '...';
    }
    
    // 使用渐变色背景
    return Container(
      width: 80,
      height: 110,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).primaryColor.withOpacity(0.8),
            Theme.of(context).primaryColorDark?.withOpacity(0.6) ?? Theme.of(context).primaryColor.withOpacity(0.6),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: Offset(1, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: Colors.transparent,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Text(
                displayTitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
                softWrap: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final novelProvider = context.watch<NovelProvider>();
    final favorites = novelProvider.favoriteNovels;
    final backgroundImage = novelProvider.bookshelfBackgroundImage;
    final backgroundColor = novelProvider.bookshelfBackgroundColor;

    if (favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
                '暂无书籍',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    }

    return Container(
        // 设置书架背景
        decoration: BoxDecoration(
          color: backgroundImage == null ? backgroundColor : null,
          image: backgroundImage != null
              ? DecorationImage(
                  image: FileImage(File(backgroundImage)),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: RefreshIndicator(
          onRefresh: () async {
            // 重新加载本地小说数据
            final novelProvider = Provider.of<NovelProvider>(context, listen: false);
            await novelProvider.init();
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final novel = favorites[index];
              return _buildBookItem(context, novel);
            },
          ),
        ),
    );
  }

  Widget _buildBookItem(BuildContext context, Novel novel) {
    final chapterCount = novel.chapterCount;
    final rawCurrent = novel.currentChapter ?? 0;
    final currentChapter = chapterCount > 0 ? rawCurrent.clamp(0, chapterCount - 1) : rawCurrent;
    final progress = chapterCount > 0 ? (currentChapter / chapterCount).toDouble() : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 封面和信息
          Expanded(
            child: Card(
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: InkWell(
                onTap: () {
                  // 导航到阅读器页面
                  Navigator.pushNamed(
                    context,
                    '/reader',
                    arguments: {
                      'novelId': novel.id,
                      'novelTitle': novel.title,
                      'chapterIndex': novel.currentChapter ?? 0,
                    },
                  );
                },
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // 封面
                      Container(
                        width: 80,
                        height: 110,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.2),
                              blurRadius: 3,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: novel.coverUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  novel.coverUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        color: Colors.grey[200],
                                        child: const Icon(Icons.book, size: 40, color: Colors.grey),
                                      ),
                                ),
                              )
                            : _buildDefaultCover(novel.title),
                      ),
                      const SizedBox(width: 16),
                      // 信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              novel.title,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '章节: ${novel.chapterCount}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.menu_book,
                                        size: 16, color: Theme.of(context).primaryColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      '第 ${currentChapter + 1}/$chapterCount 章',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // 删除按钮
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () {
                          _showDeleteDialog(context, novel);
                        },
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, Novel novel) {
    // 在异步操作前获取NavigatorState和NovelProvider
    final navigator = Navigator.of(context);
    final novelProvider = Provider.of<NovelProvider>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定要删除《${novel.title}》吗？'),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              try {
                // 先从书架移除
                novelProvider.removeFromFavorites(novel.id);
                
                // 获取应用文档目录
                final dir = await getApplicationDocumentsDirectory();
                final novelDir = Directory('${dir.path}/novels');
                
                // 删除本地文件
                final file = File('${novelDir.path}/${novel.id}');
                if (await file.exists()) {
                  await file.delete();
                }
              } catch (e) {
                print('删除文件失败: $e');
              }
              
              navigator.pop();
            },
            child: const Text(
              '确定',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
