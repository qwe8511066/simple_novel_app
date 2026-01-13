import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/novel_provider.dart';
import '../../../utils/statusBarStyle.dart';

class ReaderCatalogOverlay extends StatefulWidget {
  final String novelTitle;
  final int currentChapterIndex;
  final int totalChapters;
  final int totalPages;
  final int currentPageIndex;
  final List<String> chapterTitles;
  final VoidCallback onBack;
  final ValueChanged<int> onChapterSelect;
  final ValueChanged<int> onPageSelect;

  const ReaderCatalogOverlay({
    super.key,
    required this.novelTitle,
    required this.currentChapterIndex,
    required this.totalChapters,
    required this.totalPages,
    required this.currentPageIndex,
    required this.chapterTitles,
    required this.onBack,
    required this.onChapterSelect,
    required this.onPageSelect,
  });

  @override
  _ReaderCatalogOverlayState createState() => _ReaderCatalogOverlayState();
}

class _ReaderCatalogOverlayState extends State<ReaderCatalogOverlay> {

  // 滚动控制器，用于自动滚动到当前章节
  final ScrollController _scrollController = ScrollController();
  
  // 页码输入控制器
  final TextEditingController _pageInputController = TextEditingController();
  
  // 页码输入焦点节点
  final FocusNode _pageInputFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    
    // 初始化页码输入框内容为当前页码
    _pageInputController.text = '${widget.currentPageIndex + 1}';
    
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
    // 释放滚动控制器和输入控制器
    _scrollController.dispose();
    _pageInputController.dispose();
    _pageInputFocusNode.dispose();
    super.dispose();
  }

  // 页码跳转方法
  void _jumpToPage() {
    try {
      // 将输入的页码转换为整数
      int targetPage = int.parse(_pageInputController.text.trim());
      
      // 确保页码在有效范围内
      if (targetPage < 1) targetPage = 1;
      if (targetPage > widget.totalPages) targetPage = widget.totalPages;
      
      // 转换为0-based索引
      int targetPageIndex = targetPage - 1;
      
      // 缓存清理已在reader_page.dart的onPageSelect回调中处理
      
      // 调用页码跳转回调
      widget.onPageSelect(targetPageIndex);
    } catch (e) {
      // 如果输入无效，显示提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请输入有效的页码'),
          duration: Duration(seconds: 1),
        ),
      );
    } finally {
      // 收起键盘
      FocusScope.of(context).unfocus();
    }
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
                  // 章节列表（带滚动条）
                  Expanded(
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
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
                  ),
                  // 底部章节信息和页码跳转
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      border: Border(top: BorderSide(color: Colors.grey[300]!)),
                    ),
                    child: Column(
                      children: [
                        // 章节信息和滚动控制
                        Row(
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
                        
                        // 页码跳转
                        SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '页码：${widget.currentPageIndex + 1}/${widget.totalPages}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 60,
                                  margin: EdgeInsets.only(right: 8),
                                  child: TextField(
                                    controller: _pageInputController,
                                    focusNode: _pageInputFocusNode,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                    decoration: InputDecoration(
                                      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide(color: Colors.grey[300]!),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide(color: themeColor),
                                      ),
                                      hintText: '页码',
                                      hintStyle: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 14,
                                      ),
                                    ),
                                    onSubmitted: (value) {
                                      // 点击键盘完成按钮时跳转
                                      _jumpToPage();
                                    },
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    _jumpToPage();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: themeColor,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    minimumSize: Size(60, 36),
                                  ),
                                  child: Text(
                                    '跳转',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
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