import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/statusBarStyle.dart';
import 'reader_controller.dart';
import './reader_settings/reader_ui_overlay.dart';
import './reader_settings/reader_catalog_overlay.dart';
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
  bool _showCatalogOverlay = false; // 是否显示目录弹窗
  int _currentPageIndex = 0;

  /// 当前章节索引
  int _currentChapterIndex = 0;

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
    _pageController = PageController(initialPage: _currentPageIndex);

    // 添加章节解析完成的监听器
    widget.controller.addListener(_onControllerChange);

    // 加载阅读进度
    _loadReadingProgress().then((_) {
      // 阅读进度加载完成后，更新当前章节索引
      _updateCurrentChapterIndex();
    });
  }
  
  // 控制器变化监听
  void _onControllerChange() {
    if (mounted) {
      setState(() {
        // 重新构建UI以更新章节信息
      });
      
      // 当内容加载完成后再解析章节，避免同时进行大量IO操作
      if (widget.controller.fullContentLoaded && !widget.controller.chaptersLoaded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.controller.parseChapters();
        });
      }
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
        if (_currentPageIndex > 0 &&
            widget.controller.isValidPageIndex(_currentPageIndex - 1)) {
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
    // 移除监听器
    widget.controller.removeListener(_onControllerChange);
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
        durChapterIndex: _currentChapterIndex, // 使用计算的当前章节索引
        durChapterPos: 0, // 暂时设为0，后续可以根据实际位置逻辑调整
        durChapterPage: _currentPageIndex, // 保存当前页码作为durChapterPage
      );
    } catch (e) {
      debugPrint('保存阅读进度失败: $e');
    }
  }
  
  /// 加载阅读进度
  Future<void> _loadReadingProgress() async {
    final novelProvider = Provider.of<NovelProvider>(context, listen: false);
    try {
      final novel = novelProvider.getNovelById(widget.novelId);
      // 优先使用Legado风格的坐标系统
      if (novel.durChapterPage != null && novel.durChapterPage! > 0) {
        if (mounted) {
          setState(() {
            _currentPageIndex = novel.durChapterPage!;
            // 如果有保存的章节索引，直接使用
            if (novel.durChapterIndex != null) {
              _currentChapterIndex = novel.durChapterIndex!;
            }
            _pageController?.jumpToPage(_currentPageIndex);
          });
        }
      } else if (novel.currentPageIndex != null && novel.currentPageIndex! > 0) {
        if (mounted) {
          setState(() {
            _currentPageIndex = novel.currentPageIndex!;
            _pageController?.jumpToPage(_currentPageIndex);
          });
        }
      }
    } catch (_) {}
  }
  
  /// 更新当前章节索引
  Future<void> _updateCurrentChapterIndex() async {
    if (widget.controller.chaptersLoaded && widget.controller.chapters != null && widget.controller.chapters!.isNotEmpty) {
      try {
        // 使用异步方法获取当前页码对应的起始行号
        final startLineIndex = await widget.controller.getStartLineIndexByPageIndexAsync(_currentPageIndex);
        // 根据行号获取对应的章节索引
        final chapterIndex = widget.controller.getChapterIndexByLineIndex(startLineIndex);
        
        if (mounted && chapterIndex != _currentChapterIndex) {
          setState(() {
            _currentChapterIndex = chapterIndex;
          });
        }
      } catch (e) {
        debugPrint('更新当前章节索引失败: $e');
      }
    }
  }

  /// 处理点击事件
  void _handleTap() {
    final currentTime = DateTime.now();
    if (_lastTapTime != null &&
        currentTime.difference(_lastTapTime!).inMilliseconds < 300) {
      // 双击操作 - 可以添加双击功能，如收藏等
    } else {
      // 单击操作
      setState(() {
        if (_showUIOverlay) {
          // 如果UI弹窗已经显示，点击空白处隐藏弹窗
          _showUIOverlay = false;
        } else if (_showCatalogOverlay) {
          // 如果显示目录弹窗，先关闭目录弹窗
          _showCatalogOverlay = false;
        } else {
          // 否则切换UI弹窗显示
          _showUIOverlay = true;
        }
      });
    }
    _lastTapTime = currentTime;
  }

@override
Widget build(BuildContext context) {
  final style = const TextStyle(fontSize: 18, height: 1.8);

  final currentContext = context;

// 只监听 themeColor，其他属性改变时不触发本 Widget 重建
  final themeColor = context.select<NovelProvider, Color>((p) => p.themeColor);

  // 这里的逻辑会自动响应 themeColor 或 setState 触发的布尔值变化
  final _backgroundColor = (_showUIOverlay || _showCatalogOverlay) 
      ? themeColor 
      : Colors.transparent; // 如果显示UI或目录弹窗，背景色为主题色；否则透明
      
  return StatusBarStyle(
    // ✅ 阅读器典型：沉浸 + 白底黑字
    backgroundColor: _backgroundColor,

    child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveReadingProgress();
        if (mounted) {
          Navigator.pop(currentContext);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,

        // ❌ 不要再用 AppBar.systemOverlayStyle
        appBar: const PreferredSize(
          preferredSize: Size.fromHeight(0),
          child: SizedBox.shrink(),
        ),

        body: GestureDetector(
          onTap: _handleTap,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (ctx, c) {
                  if (!_ready) {
                    _currentStyle = style;
                    _currentSize = c.biggest;

                    _loadFirstScreenContent(c.biggest, style);

                    widget.controller.load(c.biggest, style).then((_) async {
          if (!mounted) return;

          _preLoadTargetPage();
          setState(() => _ready = true);

          await Future.delayed(const Duration(milliseconds: 50));
          _restoreReadingPosition();
          await _updateCurrentChapterIndex();
        });

                    return Container(
                      color: Colors.white,
                      child: _firstScreenReady && _firstScreenContent.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: SingleChildScrollView(
                                child: Text(
                                  _firstScreenContent,
                                  style: style,
                                ),
                              ),
                            )
                          : const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                    );
                  }

                  return PageView.builder(
                    controller: _pageController,
                    itemCount: widget.controller.totalPages,
                    onPageChanged: (index) {
                      if (index >= 0 &&
                          index < widget.controller.totalPages) {
                        setState(() {
                          _currentPageIndex = index;
                        });
                        
                        // 异步更新当前章节索引
                        _updateCurrentChapterIndex();
                      }
                    },
                    itemBuilder: (_, i) {
                      return _PageContentWidget(
                        controller: widget.controller,
                        pageIndex: i,
                        style: style,
                      );
                    },
                  );
                },
              ),

              /// UI Overlay（不会再影响状态栏）
              if (_showUIOverlay)
                ReaderUIOverlay(
                  novelTitle:
                      widget.controller.novelTitle ?? '阅读器',
                  currentPage: _currentPageIndex + 1,
                  totalPages: widget.controller.totalPages,
                  onBack: () async {
                    await _saveReadingProgress();
                    if (mounted) {
                      Navigator.pop(currentContext);
                    }
                  },
                  // 点击了目录
                  onCatalog: () {
                    setState(() {
                      _showUIOverlay = false;
                      _showCatalogOverlay = true;
                    });
                  },
                  // 点击了朗读
                  onReadAloud: () {},
                  // 点击了界面
                  onInterface: () {},
                  // 点击了设置
                  onSettings: () {},
                ),
              
              /// 目录弹窗
              if (_showCatalogOverlay)
                ReaderCatalogOverlay(
                  novelTitle: widget.controller.novelTitle ?? '阅读器',
                  currentChapterIndex: _currentChapterIndex,
                  totalChapters: widget.controller.chapters?.length ?? 0,
                  chapterTitles: widget.controller.chapters?.map((c) => c.title).toList() ?? [],
                  onBack: () {
                    setState(() {
                      _showCatalogOverlay = false;
                    });
                  },
                  onChapterSelect: (chapterIndex) async {
                    // 根据章节索引计算页码并跳转
                    if (widget.controller.chapters != null && chapterIndex >= 0 && chapterIndex < widget.controller.chapters!.length) {
                      // 获取目标章节对应的页码
                      final targetPageIndex = await widget.controller.getPageIndexByChapterIndex(chapterIndex);
                       
                      // 更新当前页码、章节索引并跳转
                      setState(() {
                        _showCatalogOverlay = false;
                        _currentPageIndex = targetPageIndex;
                        // 直接设置当前章节索引为用户点击的章节索引，避免后续更新错误
                        _currentChapterIndex = chapterIndex;
                      });
                       
                      // 跳转到目标页码
                      if (_pageController != null && mounted) {
                        _pageController!.jumpToPage(targetPageIndex);
                      }
                    }
                  },
                )
            ],
          ),
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

    _contentFuture = widget.controller
        .getPageContentAsync(widget.pageIndex)
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
            child: Text(_content, style: widget.style),
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
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
