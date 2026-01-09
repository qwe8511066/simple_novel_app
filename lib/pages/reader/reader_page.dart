import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'reader_controller.dart';
import '../../providers/novel_provider.dart';

class ReaderPage extends StatefulWidget {
  final ReaderController controller;
  final String novelId;
  
  const ReaderPage({
    super.key,
    required this.controller,
    required this.novelId,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  bool _ready = false;
  int _currentPageIndex = 0;
  int? _lastPreloadedPage;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    
    // 加载保存的阅读进度
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final novelProvider = Provider.of<NovelProvider>(context, listen: false);
      try {
        final novel = novelProvider.getNovelById(widget.novelId);
        if (novel.currentPageIndex != null && novel.currentPageIndex! > 0) {
          _currentPageIndex = novel.currentPageIndex!;
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    // 保存阅读进度
    _saveReadingProgress();
    _pageController.dispose();
    super.dispose();
  }

  /// 保存阅读进度
  void _saveReadingProgress() {
    if (!mounted) return;
    
    try {
      final novelProvider = Provider.of<NovelProvider>(context, listen: false);
      novelProvider.updateReadingProgress(
        widget.novelId,
        0,
        0.0,
        pageIndex: _currentPageIndex,
      );
    } catch (e) {
      debugPrint('保存阅读进度失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = const TextStyle(fontSize: 18, height: 1.8);

    return WillPopScope(
      onWillPop: () async {
        _saveReadingProgress();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.controller.novelTitle ?? '阅读器'),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '第 ${_currentPageIndex + 1}/${widget.controller.totalPages} 页',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (ctx, c) {
            if (!_ready) {
              // 初始化PageController时设置初始页面
              _pageController = PageController(initialPage: _currentPageIndex);
              
              widget.controller
                  .load(c.biggest, style)
                  .then((_) async {
                    if (mounted) {
                      setState(() => _ready = true);
                      // 等待页面完全构建后再跳转到保存的页码
                      await Future.delayed(const Duration(milliseconds: 100));
                      if (mounted && _currentPageIndex > 0 && _currentPageIndex < widget.controller.totalPages) {
                        // 使用animateToPage以确保跳转成功
                        _pageController.animateToPage(_currentPageIndex,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    }
                  });
              return Container(
                color: Colors.white,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      '正在加载小说内容...',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.controller.isLoading ? '处理中，请稍候...' : '已完成',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '大文件需要更多处理时间，请耐心等待',
                      style: TextStyle(fontSize: 12, color: Colors.blue[300]),
                    ),
                  ],
                ),
              );
            }

            return PageView.builder(
              controller: _pageController,
              itemCount: widget.controller.totalPages,
              onPageChanged: (index) {
                // 确保索引在有效范围内
                if (index >= 0 && index < widget.controller.totalPages) {
                  setState(() {
                    _currentPageIndex = index;
                  });
                }
              },
              itemBuilder: (_, i) => FutureBuilder<String>(
                future: widget.controller.getPageContentAsync(i),
                builder: (context, snapshot) {
                  String content = '';
                  if (snapshot.hasData) {
                    content = snapshot.data!;
                  } else {
                    content = '加载中...';
                  }
                  
                  // 预加载相邻页面，但仅在当前显示的页面上执行
                  if (snapshot.hasData && i == _currentPageIndex && (i != _lastPreloadedPage || _lastPreloadedPage == null)) {
                    _lastPreloadedPage = i;
                    // 预加载当前页的相邻页面
                    widget.controller.preloadAdjacentPages(i);
                  }
                  
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      child: Text(
                        content,
                        style: style,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
