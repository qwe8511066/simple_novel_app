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

  /// 从持久化进度恢复时保存的章节索引（优先用章节来还原页码）
  int? _savedChapterIndexFromStorage;

  /// 是否已经根据持久化进度完成过一次恢复，避免重复恢复导致位置抖动
  bool _restoredFromStorage = false;

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

      // 关键：当控制器状态变化（特别是章节解析完成、分页重建）后，
      // 如果还没有从持久化进度恢复过位置，尝试恢复一次
      // 但恢复逻辑内部会检查分页引擎是否已重建完成，确保在正确时机执行
      if (!_restoredFromStorage) {
        // 使用Future.microtask确保在当前帧结束后执行恢复操作
        Future.microtask(() => _restoreReadingPosition());
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
  /// 重要：必须等待分页引擎基于章节锚点重建完成后才执行恢复
  Future<void> _restoreReadingPosition() async {
    // 已经成功恢复过一次位置则不再重复
    if (_restoredFromStorage) return;

    // 1. 必须等待内容完全加载
    if (!widget.controller.fullContentLoaded) {
      debugPrint('恢复位置：等待内容加载完成');
      return;
    }

    // 2. 关键：必须等待分页引擎基于章节锚点重建完成
    // 如果分页引擎还没重建，页码映射是错的，恢复会错乱
    if (!widget.controller.paginationRebuiltWithChapters) {
      debugPrint('恢复位置：等待分页引擎基于章节锚点重建完成');
      return;
    }

    // 3. 如果有章节索引，优先使用「章节索引」来恢复位置
    if (_savedChapterIndexFromStorage != null) {
      if (!(widget.controller.chaptersLoaded &&
          widget.controller.chapters != null &&
          _savedChapterIndexFromStorage! >= 0 &&
          _savedChapterIndexFromStorage! < (widget.controller.chapters?.length ?? 0))) {
        // 章节信息尚未就绪，稍后再尝试
        debugPrint('恢复位置：等待章节信息就绪');
        return;
      }

      try {
        final chapterIndex = _savedChapterIndexFromStorage!;
        debugPrint('恢复位置：使用章节索引 $chapterIndex');
        
        // 根据章节索引精确计算对应页码（此时分页引擎已重建，页码映射正确）
        final targetPageIndex = await widget.controller.getPageIndexByChapterIndex(chapterIndex);
        
        debugPrint('恢复位置：章节 $chapterIndex 对应页码 $targetPageIndex');

        if (!mounted) return;

        setState(() {
          _currentPageIndex = targetPageIndex;
          _currentChapterIndex = chapterIndex;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _pageController == null) return;
          _pageController!.jumpToPage(targetPageIndex);
          debugPrint('恢复位置：已跳转到页码 $targetPageIndex（章节 $chapterIndex）');
        });

        _restoredFromStorage = true;
        _savedChapterIndexFromStorage = null;
      } catch (e) {
        debugPrint('根据章节恢复阅读位置失败: $e');
      }
      return;
    }

    // 4. 没有章节信息时，退回到旧的：按页码恢复（但也要等分页重建完成）
    if (_currentPageIndex >= 0 &&
        widget.controller.isValidPageIndex(_currentPageIndex)) {
      if (!mounted) return;

      debugPrint('恢复位置：使用页码 $_currentPageIndex（无章节信息）');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !widget.controller.isValidPageIndex(_currentPageIndex) ||
            _pageController == null) {
          return;
        }

        if (_currentPageIndex == 0) {
          _pageController!.jumpToPage(_currentPageIndex);
        } else {
          _pageController!.animateToPage(
            _currentPageIndex,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeInOut,
          );
        }
      });

      _restoredFromStorage = true;
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
      // 确保当前章节索引是有效的
      int validChapterIndex = _currentChapterIndex;
      if (widget.controller.chapters != null && widget.controller.chapters!.isNotEmpty) {
        validChapterIndex = validChapterIndex.clamp(0, widget.controller.chapters!.length - 1);
      }
      
      final novelProvider = Provider.of<NovelProvider>(context, listen: false);
      await novelProvider.updateReadingProgress(
        widget.novelId,
        0,
        0.0,
        pageIndex: _currentPageIndex,
        durChapterIndex: validChapterIndex, // 使用有效的当前章节索引
        durChapterPos: 0, // 暂时设为0，后续可以根据实际位置逻辑调整
        durChapterPage: _currentPageIndex, // 保存当前页码作为durChapterPage
      );
      
      debugPrint('保存阅读进度: 章节$validChapterIndex, 页码$_currentPageIndex');
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
            // 如果有保存的章节索引，记录下来，待内容和章节解析完成后再用章节精确恢复
            if (novel.durChapterIndex != null) {
              _savedChapterIndexFromStorage = novel.durChapterIndex!;
            }
          });
        }
      } else if (novel.currentPageIndex != null && novel.currentPageIndex! > 0) {
        if (mounted) {
          setState(() {
            _currentPageIndex = novel.currentPageIndex!;
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

  /// 打开目录前，先根据当前页精确更新一次章节索引，保证高亮正确
  void _openCatalog() async {
    try {
      await _updateCurrentChapterIndex();
    } catch (e) {
      debugPrint('打开目录前更新章节索引失败: $e');
    }

    if (!mounted) return;

    setState(() {
      _showUIOverlay = false;
      _showCatalogOverlay = true;
    });
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
                  // 顶部 UI 里展示的总页数，用实际估算值，不带额外缓冲
                  totalPages: widget.controller.actualTotalPages,
                  onBack: () async {
                    await _saveReadingProgress();
                    if (mounted) {
                      Navigator.pop(currentContext);
                    }
                  },
                  // 点击了目录
                  onCatalog: _openCatalog,
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
                  totalPages: widget.controller.actualTotalPages,
                  currentPageIndex: _currentPageIndex,
                  chapterTitles: widget.controller.chapters?.map((c) => c.title).toList() ?? [],
                  onBack: () {
                    setState(() {
                      _showCatalogOverlay = false;
                    });
                  },
                  onChapterSelect: (chapterIndex) async {
                    // 根据章节索引计算页码并跳转
                    if (widget.controller.chapters != null && chapterIndex >= 0 && chapterIndex < widget.controller.chapters!.length) {
                      // 先预计算目标章节附近的页面边界，提高跳转准确性
                      // 获取目标章节对应的行号
                      final targetLineIndex = widget.controller.getLineIndexByChapterIndex(chapterIndex);
                      
                      // 估算目标页码的大致范围
                      final estimatedPage = widget.controller.estimatePageFromLineIndex(targetLineIndex);
                      
                      // 预计算目标页面前后几页的边界，确保跳转准确
                      // 预计算范围：目标页码前后各5页
                      final preloadStart = (estimatedPage - 5).clamp(0, double.infinity).toInt();
                      final preloadEnd = estimatedPage + 5;
                      
                      // 异步预计算这些页面的边界（不阻塞UI）
                      Future.microtask(() async {
                        for (int i = preloadStart; i <= preloadEnd; i++) {
                          try {
                            await widget.controller.getStartLineIndexByPageIndexAsync(i);
                            // 同时预加载页面内容，确保边界计算准确
                            await widget.controller.getPageContentAsync(i);
                          } catch (e) {
                            // 忽略预加载错误，不影响主流程
                          }
                        }
                      });
                      
                      // 获取目标章节对应的精确页码
                      final targetPageIndex = await widget.controller.getPageIndexByChapterIndex(chapterIndex);
                        
                      // 更新当前页码、章节索引并跳转
                      if (mounted) {
                        setState(() {
                          _showCatalogOverlay = false;
                          _currentPageIndex = targetPageIndex;
                          // 直接设置当前章节索引为用户点击的章节索引，避免后续更新错误
                          _currentChapterIndex = chapterIndex;
                        });
                      }
                        
                      // 注意：不再清理所有分页缓存，因为我们已经预计算了目标页面附近的边界
                      // 只清理页面内容缓存，保留页面边界缓存
                      widget.controller.clearPageContentCacheOnly();
                        
                      // 跳转到目标页码
                      if (_pageController != null && mounted) {
                        _pageController!.animateToPage(
                          targetPageIndex,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    }
                  },
                  onPageSelect: (pageIndex) async {
                    // 直接跳转到指定页码
                    if (mounted) {
                      setState(() {
                        _showCatalogOverlay = false;
                        _currentPageIndex = pageIndex;
                      });
                    }
                    
                    // 清理所有分页缓存，避免缓存污染
                    widget.controller.clearAllPaginationCache();
                    
                    // 更新当前章节索引
                    // 首先获取该页码对应的起始行号
                    final startLineIndex = await widget.controller.getStartLineIndexByPageIndexAsync(pageIndex);
                    // 然后根据起始行号获取章节索引
                    final chapterIndex = widget.controller.getChapterIndexByLineIndex(startLineIndex);
                    if (mounted) {
                      setState(() {
                        _currentChapterIndex = chapterIndex;
                      });
                    }
                    
                    // 跳转到目标页码
                    if (_pageController != null && mounted) {
                      _pageController!.animateToPage(
                        pageIndex,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
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
