import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'reader_controller.dart';
import './reader_settings/reader_ui_overlay.dart';
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
  bool _showUIOverlay = false; // 是否显示UI弹窗
  int _currentPageIndex = 0;
  int? _lastPreloadedPage;
  PageController? _pageController;
  String _firstScreenContent = ''; // 首屏内容缓存
  DateTime? _lastTapTime; // 记录上次点击时间
  
  // 用于保存当前页面的文本样式和尺寸
  TextStyle? _currentStyle;
  Size? _currentSize;

  @override
  void initState() {
    super.initState();
    // 使用传入的初始页码，如果为0则尝试从provider获取
    _currentPageIndex = widget.initialPageIndex;

    // 初始化PageController，避免在build中初始化导致的重建
    _pageController = PageController(
      initialPage: _currentPageIndex,
    );

    // 如果初始页码为0，再尝试从provider获取保存的阅读进度
    if (_currentPageIndex == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final novelProvider = Provider.of<NovelProvider>(
          context,
          listen: false,
        );
        try {
          final novel = novelProvider.getNovelById(widget.novelId);
          // 优先使用Legado风格的坐标系统
          if (novel.durChapterPage != null && novel.durChapterPage! > 0) {
            _currentPageIndex = novel.durChapterPage!;
            // 调整页面控制器到正确的初始页面
            if (_pageController != null && mounted) {
              _pageController!.jumpToPage(_currentPageIndex);
            }
          } else if (novel.currentPageIndex != null &&
              novel.currentPageIndex! > 0) {
            _currentPageIndex = novel.currentPageIndex!;
            // 调整页面控制器到正确的初始页面
            if (_pageController != null && mounted) {
              _pageController!.jumpToPage(_currentPageIndex);
            }
          }
        } catch (_) {}
      });
    }
  }

  /// 预加载目标页面和相邻页面
  void _preLoadTargetPage() {
    // 在后台预加载目标页面和相邻页面的内容
    Future.microtask(() async {
      try {
        // 预加载目标页面
        if (widget.controller.isValidPageIndex(_currentPageIndex)) {
          await widget.controller.getPageContentAsync(_currentPageIndex);
        }
        // 预加载前一页（如果存在）
        if (_currentPageIndex > 0 && widget.controller.isValidPageIndex(_currentPageIndex - 1)) {
          await widget.controller.getPageContentAsync(_currentPageIndex - 1);
        }
        // 预加载后一页（如果存在）
        if (widget.controller.isValidPageIndex(_currentPageIndex + 1)) {
          await widget.controller.getPageContentAsync(_currentPageIndex + 1);
        }
      } catch (e) {
        // 预加载失败不影响主流程
        debugPrint('预加载目标页面失败: $e');
      }
    });
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
          if (mounted &&
              widget.controller.isValidPageIndex(_currentPageIndex) &&
              _pageController != null) {
            // 使用更平滑的跳转方式，减少视觉跳跃感
            // 如果页面索引为0，直接跳转；否则使用较短的动画
            if (_currentPageIndex == 0) {
              _pageController?.jumpToPage(_currentPageIndex);
            } else {
              // 使用非常短的动画时间来平滑过渡，减少跳跃感
              _pageController?.animateToPage(
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
    _pageController?.dispose();
    super.dispose();
  }

  /// 保存阅读进度
  Future<void> _saveReadingProgress() async {
    if (!mounted) return;

    try {
      final novelProvider = Provider.of<NovelProvider>(context, listen: false);
      await novelProvider.updateReadingProgress(
        widget.novelId,
        0,
        0.0,
        pageIndex: _currentPageIndex,
        durChapterIndex: 0, // 暂时设为0，后续可以根据实际章节逻辑调整
        durChapterPos: 0, // 暂时设为0，后续可以根据实际位置逻辑调整
        durChapterPage: _currentPageIndex, // 保存当前页码作为durChapterPage
      );
    } catch (e) {
      debugPrint('保存阅读进度失败: $e');
    }
  }

  /// 处理点击事件
  void _handleTap() {
    final currentTime = DateTime.now();
    if (_lastTapTime != null &&
        currentTime.difference(_lastTapTime!).inMilliseconds < 300) {
      // 双击操作 - 可以添加双击功能，如收藏等
    } else {
      // 单击操作 - 切换UI弹窗显示
      setState(() {
        _showUIOverlay = !_showUIOverlay;
      });
    }
    _lastTapTime = currentTime;
  }

  @override
  Widget build(BuildContext context) {
    final style = const TextStyle(fontSize: 18, height: 1.8);

    final currentContext = context;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _saveReadingProgress();
          if (mounted) {
            Navigator.pop(currentContext);
          }
        },
        child: Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(0),
            child: AppBar(elevation: 0),
          ),
          body: GestureDetector(
            onTap: _handleTap,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (ctx, c) {
                    if (!_ready) {
                      // 保存当前样式和尺寸
                      _currentStyle = style;
                      _currentSize = c.biggest;
                      
                      // 快速加载首屏内容以立即显示
                      _loadFirstScreenContent(c.biggest, style);

                      // 同时在后台加载完整内容
                      widget.controller.load(c.biggest, style).then((_) async {
                        if (mounted) {
                          // 预加载目标页面和相邻页面
                          _preLoadTargetPage();
                          
                          setState(() => _ready = true);
                          // 等待一小段时间确保页面控制器就绪
                          await Future.delayed(
                            const Duration(milliseconds: 50),
                          );
                          // 使用专门的进度恢复方法
                          _restoreReadingPosition();
                        }
                      });

                      // 显示首屏内容或加载指示器
                      return Container(
                        color: Colors.white,
                        child: _firstScreenReady && _firstScreenContent.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: SingleChildScrollView(
                                  child: Text(_firstScreenContent, style: style),
                                ),
                              )
                            : Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                              ),
                      );
                    }

                    return PageView.builder(
                      controller: _pageController,
                      itemCount: widget.controller.totalPages,
                      onPageChanged: (index) {
                        // 确保索引在有效范围内
                        if (index >= 0 &&
                            index < widget.controller.totalPages) {
                          setState(() {
                            _currentPageIndex = index;
                          });
                        }
                      },
                      itemBuilder: (_, i) {
                        // 使用自定义的页面内容组件，避免FutureBuilder的重建问题
                        return _PageContentWidget(
                          controller: widget.controller,
                          pageIndex: i,
                          style: style,
                        );
                      },
                    );
                  },
                ),
                // UI弹窗（点击时显示）
                if (_showUIOverlay)
                  ReaderUIOverlay(
                    novelTitle: widget.controller.novelTitle ?? '阅读器',
                    currentPage: _currentPageIndex + 1,
                    totalPages: widget.controller.totalPages,
                    onBack: () async {
                      await _saveReadingProgress();
                      if (mounted) {
                        Navigator.pop(currentContext);
                      }
                    },
                    onCatalog: () {
                      // 目录
                      print('目录');
                    },
                    onReadAloud: () {
                      // 朗读
                      print('朗读');
                    },
                    onInterface: () {
                      // 界面
                      print('界面');
                    },
                    onSettings: () {
                      // 设置
                      print('设置');
                    },
                  ),
              ],
            ),
          ),
        ),
    );
  }
}

/// 自定义页面内容组件，避免FutureBuilder的重建问题
class _PageContentWidget extends StatefulWidget {
  final ReaderController controller;
  final int pageIndex;
  final TextStyle style;

  const _PageContentWidget({
    required this.controller,
    required this.pageIndex,
    required this.style,
  });

  @override
  _PageContentWidgetState createState() => _PageContentWidgetState();
}

class _PageContentWidgetState extends State<_PageContentWidget> {
  late Future<String> _contentFuture;
  String _content = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void didUpdateWidget(_PageContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有当页面索引或控制器变化时才重新加载内容
    if (widget.pageIndex != oldWidget.pageIndex ||
        widget.controller != oldWidget.controller) {
      _loadContent();
    }
  }

  void _loadContent() {
    setState(() {
      _isLoading = true;
    });
    
    _contentFuture = widget.controller.getPageContentAsync(widget.pageIndex)
      .then((content) {
        if (mounted) {
          setState(() {
            _content = content;
            _isLoading = false;
          });
        }
        return content;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Text(
              _content,
              style: widget.style,
            ),
          ),
        ),
        if (_isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity(0.5),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
