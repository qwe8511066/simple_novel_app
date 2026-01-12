import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'reader_controller.dart';
import '../../providers/novel_provider.dart';

class ReaderPage extends StatefulWidget {
  final ReaderController controller;
  final String novelId;
  final int initialPageIndex;
  
  const ReaderPage({
    super.key,
    required this.controller,
    required this.novelId,
    this.initialPageIndex = 0,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  bool _ready = false;
  bool _firstScreenReady = false; // 是否已准备好首屏内容
  int _currentPageIndex = 0;
  int? _lastPreloadedPage;
  late PageController _pageController;
  String _firstScreenContent = ''; // 首屏内容缓存

  @override
  void initState() {
    super.initState();
    
    // 使用传入的初始页码，如果为0则尝试从provider获取
    _currentPageIndex = widget.initialPageIndex;
    
    // 如果初始页码为0，再尝试从provider获取保存的阅读进度
    if (_currentPageIndex == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final novelProvider = Provider.of<NovelProvider>(context, listen: false);
        try {
          final novel = novelProvider.getNovelById(widget.novelId);
          // 优先使用Legado风格的坐标系统
          if (novel.durChapterPage != null && novel.durChapterPage! > 0) {
            _currentPageIndex = novel.durChapterPage!;
          } else if (novel.currentPageIndex != null && novel.currentPageIndex! > 0) {
            _currentPageIndex = novel.currentPageIndex!;
          }
        } catch (_) {}
      });
    }
    
    // 预加载目标页面以减少跳转延迟
    _preLoadTargetPage();
  }
  
  /// 预加载目标页面
  void _preLoadTargetPage() {
    if (_currentPageIndex > 0) {
      // 在后台预加载目标页面的内容
      Future.microtask(() async {
        if (widget.controller.hasCachedData && 
            widget.controller.isValidPageIndex(_currentPageIndex)) {
          try {
            // 预加载目标页面以减少跳转时的延迟
            await widget.controller.getPageContentAsync(_currentPageIndex);
          } catch (e) {
            // 预加载失败不影响主流程
          }
        }
      });
    }
  }

  /// 加载首屏内容并显示
  void _loadFirstScreenContent(Size size, TextStyle style) {
    if (!_firstScreenReady) {
      widget.controller.getFirstScreenContent(size, style).then((content) {
        if (mounted) {
          setState(() {
            _firstScreenContent = content;
            _firstScreenReady = true;
          });
        }
      });
    }
  }
  
  /// 根据保存的进度精确恢复阅读位置
  Future<void> _restoreReadingPosition() async {
    // 确保页面已经完全加载并且有有效的页码
    if (widget.controller.fullContentLoaded && 
        _currentPageIndex >= 0 && 
        widget.controller.isValidPageIndex(_currentPageIndex)) {
      
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.controller.isValidPageIndex(_currentPageIndex)) {
            // 使用更平滑的跳转方式，减少视觉跳跃感
            // 如果页面索引为0，直接跳转；否则使用较短的动画
            if (_currentPageIndex == 0) {
              _pageController.jumpToPage(_currentPageIndex);
            } else {
              // 使用非常短的动画时间来平滑过渡，减少跳跃感
              _pageController.animateToPage(
                _currentPageIndex,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeInOut,
              );
            }
          }
        });
      }
    }
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
        durChapterIndex: 0, // 暂时设为0，后续可以根据实际章节逻辑调整
        durChapterPos: 0,  // 暂时设为0，后续可以根据实际位置逻辑调整
        durChapterPage: _currentPageIndex, // 保存当前页码作为durChapterPage
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
              
              // 快速加载首屏内容以立即显示
              _loadFirstScreenContent(c.biggest, style);
              
              // 同时在后台加载完整内容
              widget.controller
                  .load(c.biggest, style)
                  .then((_) async {
                    if (mounted) {
                      setState(() => _ready = true);
                      // 等待一小段时间确保页面控制器就绪
                      await Future.delayed(const Duration(milliseconds: 50));
                      // 使用专门的进度恢复方法
                      _restoreReadingPosition();
                    }
                  });
              
              // 显示首屏内容或加载指示器
              return Container(
                color: Colors.white,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_firstScreenReady && _firstScreenContent.isNotEmpty)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SingleChildScrollView(
                            child: Text(
                              _firstScreenContent,
                              style: style,
                            ),
                          ),
                        ),
                      )
                    else
                      CircularProgressIndicator(value: widget.controller.fullContentLoaded ? 1.0 : null,),
                    const SizedBox(height: 20),
                    Text(
                      _firstScreenReady ? '首屏内容已加载' : '正在准备阅读环境...',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.controller.isLoading ? '处理中 (${widget.controller.getTotalPages()} 页)' : '加载完成',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '完整内容在后台加载中',
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
