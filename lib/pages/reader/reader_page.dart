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
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    
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
                  '第 ${_currentPageIndex + 1}/${widget.controller.pages.length} 页',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (ctx, c) {
            if (!_ready) {
              widget.controller
                  .load(c.biggest, style)
                  .then((_) {
                    if (mounted) {
                      setState(() => _ready = true);
                      // 加载完成后跳转到保存的页码
                      if (_currentPageIndex < widget.controller.totalPages) {
                        Future.delayed(const Duration(milliseconds: 100), () {
                          if (mounted) {
                            _pageController.jumpToPage(_currentPageIndex);
                          }
                        });
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
                      widget.controller.isLoading ? '处理中...' : '已完成',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                  ],
                ),
              );
            }

            return PageView.builder(
              controller: _pageController,
              itemCount: widget.controller.totalPages,
              onPageChanged: (index) {
                setState(() {
                  _currentPageIndex = index;
                });
              },
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Text(
                    widget.controller.getPageContent(i),
                    style: style,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
