import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/novel_provider.dart';
import '../../../utils/statusBarStyle.dart';

class ReaderCatalogOverlay extends StatefulWidget {
  final String novelTitle;
  final int currentChapterIndex;
  final int totalChapters;
  final List<String> chapterTitles;
  final VoidCallback onBack;
  final ValueChanged<int> onChapterSelect;

  const ReaderCatalogOverlay({
    super.key,
    required this.novelTitle,
    required this.currentChapterIndex,
    required this.totalChapters,
    required this.chapterTitles,
    required this.onBack,
    required this.onChapterSelect,
  });

  @override
  _ReaderCatalogOverlayState createState() => _ReaderCatalogOverlayState();
}

class _ReaderCatalogOverlayState extends State<ReaderCatalogOverlay> {

  // 滚动控制器，用于自动滚动到当前章节
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    
    // 组件初始化后，自动滚动到当前章节
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.currentChapterIndex >= 0 && widget.currentChapterIndex < widget.chapterTitles.length) {
        // 使用固定的列表项高度
        const double itemHeight = 52.0;
        
        // 获取列表可见区域的高度
        final double viewportHeight = _scrollController.position.viewportDimension;
        
        // 计算滚动位置：当前章节位置 - 视口高度的一半 + 列表项高度的一半
        // 这样可以让当前章节居中显示
        double scrollPosition = widget.currentChapterIndex * itemHeight - (viewportHeight / 2) + (itemHeight / 2);
        
        // 确保滚动位置不小于0
        scrollPosition = scrollPosition < 0 ? 0 : scrollPosition;
        
        // 确保滚动位置不超过最大滚动范围
        final maxScrollExtent = _scrollController.position.maxScrollExtent;
        scrollPosition = scrollPosition > maxScrollExtent ? maxScrollExtent : scrollPosition;
        
        // 执行滚动
        _scrollController.animateTo(
          scrollPosition,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    // 释放滚动控制器
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final novelProvider = Provider.of<NovelProvider>(context);
    final themeColor = novelProvider.themeColor;
    final double statusBarHeight = StatusBarScope.of(context).statusBarHeight;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 背景遮罩
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onBack,
              child: Container(
                color: Colors.black.withOpacity(0.5),
              ),
            ),
          ),
          // 目录弹窗
          Positioned(
            top: statusBarHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  // 顶部标题栏
                  Container(
                    color: themeColor,
                    child: AppBar(
                      title: const Text(
                        '目录',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: themeColor,
                      elevation: 0,
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: widget.onBack,
                      ),
                      actions: [
                        // 书签按钮
                        TextButton(
                          onPressed: () {
                            // 书签功能可以在后续实现
                          },
                          child: const Text(
                            '书签',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                        // 搜索按钮
                        IconButton(
                          icon: const Icon(Icons.search, color: Colors.white),
                          onPressed: () {
                            // 搜索功能可以在后续实现
                          },
                        ),
                        // 更多按钮
                        IconButton(
                          icon: const Icon(Icons.more_vert, color: Colors.white),
                          onPressed: () {
                            // 更多功能可以在后续实现
                          },
                        ),
                      ],
                    ),
                  ),
                  // 章节列表
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.zero,
                      itemCount: widget.chapterTitles.length,
                      // 设置固定的列表项高度，确保滚动位置计算准确
                      itemExtent: 52.0, // 固定列表项高度为52px
                      itemBuilder: (context, index) {
                        final isCurrentChapter = index == widget.currentChapterIndex;
                        return ListTile(
                          title: Text(
                            widget.chapterTitles[index],
                            style: TextStyle(
                              color: isCurrentChapter ? themeColor : Colors.black87,
                              fontWeight: isCurrentChapter ? FontWeight.bold : FontWeight.normal,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          leading: isCurrentChapter
                              ? Icon(Icons.check, color: themeColor)
                              : null,
                          onTap: () {
                            widget.onChapterSelect(index);
                          },
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          tileColor: isCurrentChapter ? Colors.grey[100] : null,
                        );
                      },
                    ),
                  ),
                  // 底部章节信息
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      border: Border(top: BorderSide(color: Colors.grey[300]!)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '第 ${widget.currentChapterIndex + 1}章/${widget.totalChapters}章',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_up, size: 24),
                              onPressed: () {
                              // 滚动到顶部
                              _scrollController.animateTo(
                                0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36),
                            ),
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down, size: 24),
                              onPressed: () {
                              // 滚动到底部
                              _scrollController.animateTo(
                                _scrollController.position.maxScrollExtent,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}