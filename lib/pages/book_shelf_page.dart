import 'package:flutter/material.dart';
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
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final novel = favorites[index];
        return _buildBookItem(context, novel);
      },
    );
  }

  Widget _buildBookItem(BuildContext context, Novel novel) {
    final currentChapter = novel.currentChapter ?? 0;
    final chapterCount = novel.chapterCount;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/reader',
            arguments: {
              'novelId': novel.id,
              'chapterIndex': currentChapter,
            },
          );
        },
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
                    : const Icon(Icons.book, size: 40),
              ),
              const SizedBox(width: 16),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      novel.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      novel.author,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.menu_book,
                            size: 16, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          '读到第 ${currentChapter + 1} 章 / 共 $chapterCount 章',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: chapterCount > 0 ? currentChapter / chapterCount : 0,
                      backgroundColor: Colors.grey[200],
                      color: Colors.blue,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, Novel novel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text('确定要从书架中移除《${novel.title}》吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Provider.of<NovelProvider>(context, listen: false)
                  .removeFromFavorites(novel.id);
              Navigator.pop(context);
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
