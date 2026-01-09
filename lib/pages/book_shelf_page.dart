import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/novel_provider.dart';
import '../models/novel.dart';


/// 书架页面
class BookshelfPage extends StatelessWidget {
  const BookshelfPage({super.key});

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
    final currentChapter = novel.currentChapter ?? 0;
    final chapterCount = novel.chapterCount;
    final progress = chapterCount > 0 ? (currentChapter / chapterCount).toDouble() : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          // 直接导航到阅读器页面
          Navigator.pushNamed(
            context,
            '/reader',
            arguments: {
              'novelId': novel.id,
              'chapterIndex': novel.currentChapter ?? 0,
            },
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 封面
              Container(
                width: 80,
                height: 110,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.3),
                      blurRadius: 4,
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
                              const Icon(Icons.book, size: 40),
                        ),
                      )
                    : Icon(Icons.book, size: 40, color: Theme.of(context).primaryColor),
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
                      novel.author,
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
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 6,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                      ),
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
