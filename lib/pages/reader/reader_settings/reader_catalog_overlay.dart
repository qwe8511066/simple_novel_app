import 'dart:async';
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
    
    // 搜索相关状态
    bool _isSearchMode = false;
    String _searchQuery = '';
    List<Map<String, dynamic>> _filteredChapterTitles = [];
    Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    
    // 初始化过滤后的章节列表
    _filteredChapterTitles = widget.chapterTitles.asMap().entries.map((entry) => {
      'index': entry.key,
      'title': entry.value
    }).toList();
    
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
    // 释放滚动控制器和计时器
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }
  
  // 切换搜索模式
  void _toggleSearchMode() {
    setState(() {
      _isSearchMode = !_isSearchMode;
      if (!_isSearchMode) {
        // 退出搜索模式时清空搜索内容
        _searchQuery = '';
        _resetFilter();
      }
    });
  }
  
  // 重置过滤结果
  void _resetFilter() {
    _filteredChapterTitles = widget.chapterTitles.asMap().entries.map((entry) => {
      'index': entry.key,
      'title': entry.value
    }).toList();
  }
  
  // 搜索变化处理（带防抖）
  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
    
    // 取消之前的计时器
    _debounceTimer?.cancel();
    
    // 设置新的计时器，500毫秒后执行搜索
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (query.isEmpty) {
        _resetFilter();
      } else {
        // 过滤章节标题
        _filteredChapterTitles = widget.chapterTitles.asMap().entries
            .where((entry) => entry.value.toLowerCase().contains(query.toLowerCase()))
            .map((entry) => {
              'index': entry.key,
              'title': entry.value
            })
            .toList();
      }
      
      setState(() {});
    });
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
                      title: _isSearchMode
                          ? TextField(
                              autofocus: true,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              decoration: InputDecoration(
                                hintText: '搜索章节...',
                                hintStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
                                border: InputBorder.none,
                              ),
                              onChanged: _onSearchChanged,
                            )
                          : const Text(
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
                        icon: Icon(
                          _isSearchMode ? Icons.close : Icons.arrow_back,
                          color: Colors.white,
                        ),
                        onPressed: _isSearchMode ? _toggleSearchMode : widget.onBack,
                      ),
                      actions: _isSearchMode
                          ? []
                          : [
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
                                onPressed: _toggleSearchMode,
                              ),
                            ],
                    ),
                  ),
                  // 章节列表
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.zero,
                      itemCount: _filteredChapterTitles.length,
                      // 设置固定的列表项高度，确保滚动位置计算准确
                      itemExtent: 52.0, // 固定列表项高度为52px
                      itemBuilder: (context, listIndex) {
                        final chapterData = _filteredChapterTitles[listIndex];
                        final chapterIndex = chapterData['index'] as int;
                        final chapterTitle = chapterData['title'] as String;
                        final isCurrentChapter = chapterIndex == widget.currentChapterIndex;
                        return ListTile(
                          title: Text(
                            chapterTitle,
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
                            widget.onChapterSelect(chapterIndex);
                          },
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          tileColor: isCurrentChapter ? Colors.grey[100] : null,
                        );
                      },
                    ),
                  ),
                    // 底部章节信息
                  _isSearchMode
                      ? const SizedBox() // 搜索模式下隐藏底部信息栏
                      : Container(
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