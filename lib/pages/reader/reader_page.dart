import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'reader_controller.dart';
import '../../providers/novel_provider.dart';
import '../../utils/statusBarStyle.dart';
import '../../utils/volume_key_controller.dart';
import '../../utils/reader_turn_animations.dart';
import './reader_settings/reader_ui_overlay.dart';
import './reader_settings/reader_catalog_overlay.dart';
import './reader_settings/reader_settings_overlay.dart';

/// 阅读器主页面组件
class ReaderPage extends StatefulWidget {
  final ReaderController controller; // 阅读器控制器，管理页面加载和分页
  final String novelId; // 当前阅读的小说ID
  final int? startChapterIndex; // 可选的起始章节索引

  const ReaderPage({
    super.key,
    required this.controller,
    required this.novelId,
    this.startChapterIndex,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  bool _ready = false; // 阅读内容是否准备就绪
  int _currentPageIndex = 0; // 当前页码索引
  PageController? _pageController; // 页面控制器，用于控制PageView的滚动和动画
  int _startSegmentIndex = 0; // 起始分段索引
  int _startPageInSegment = 0; // 分段内的起始页码
  int? _startByteOffset; // 起始字节偏移，用于精确恢复阅读位置
  bool _initializing = false; // 是否正在初始化
  bool _jumpingChapter = false; // 是否正在跳转到新章节
  int _currentChapterIndex = 0; // 当前章节索引

  static const MethodChannel _volumeChannel = MethodChannel('com.example.app/volume_keys'); // 音量键监听通道
  bool _volumeChannelBound = false; // 音量键通道是否已绑定
  
  bool _showUIOverlay = false; // 是否显示UI弹窗，默认显示以方便用户操作
  bool _showCatalogOverlay = false; // 是否显示目录弹窗
  bool _showSettingsOverlay = false; // 是否显示设置弹窗

  late final NovelProvider _novelProvider; // 小说状态管理提供者

  Size? _lastLayoutSize; // 上次布局大小
  Size? _lastContentSize; // 上次内容区域大小
  TextStyle? _lastTextStyle; // 上次使用的文本样式

  Timer? _rePaginateDebounce; // 重新分页的防抖定时器
  String? _lastTypographyKey; // 上次排版配置的唯一标识
  String? _lastCustomFontPath; // 上次使用的自定义字体路径

  /// 处理音量键翻页命令
  Future<void> _handleVolumeCommand(String method) async {
    // 如果阅读内容未准备就绪，直接返回
    if (!_ready) return;
    // 如果有任何弹窗显示，不处理音量键翻页
    if (_showCatalogOverlay || _showSettingsOverlay || _showUIOverlay) return;

    final novelProvider = Provider.of<NovelProvider>(context, listen: false);
    // 如果未启用音量键翻页，直接返回
    if (!novelProvider.volumeKeyPageTurning) return;

    final pc = _pageController;
    if (pc == null || !pc.hasClients) return;

    if (method == 'volume_down') {
      // 音量减小键：下一页
      final next = (_currentPageIndex + 1).clamp(0, widget.controller.pages.length - 1);
      if (next != _currentPageIndex) {
        // 根据当前选择的翻页动画设置动画曲线
        Curve curve = _getAnimationCurve(novelProvider.readerTurnAnimation);
        pc.animateToPage(next, duration: const Duration(milliseconds: 300), curve: curve);
      }
    } else if (method == 'volume_up') {
      // 音量增大键：上一页
      final prev = (_currentPageIndex - 1).clamp(0, widget.controller.pages.length - 1);
      if (prev != _currentPageIndex) {
        // 根据当前选择的翻页动画设置动画曲线
        Curve curve = _getAnimationCurve(novelProvider.readerTurnAnimation);
        pc.animateToPage(prev, duration: const Duration(milliseconds: 300), curve: curve);
      }
    }
  }

  /// 跳转到指定章节
  Future<void> _jumpToChapter(int chapterIndex) async {
    final layoutSize = _lastContentSize;
    final textStyle = _lastTextStyle;
    if (layoutSize == null || textStyle == null) return;

    // 确保章节索引已加载
    await widget.controller.ensureChapterIndexLoaded();

    // 防止重复跳转
    if (_jumpingChapter) return;
    _jumpingChapter = true;

    try {
      setState(() {
        _ready = false;
      });
      // 释放旧的页面控制器
      _pageController?.dispose();
      _pageController = null;

      // 获取章节起始位置
      final byteOffset = widget.controller.chapterStartOffsetAt(chapterIndex);
      // 跳转到指定位置
      final targetPage = await widget.controller.jumpToByteOffset(
        byteOffset,
        layoutSize,
        textStyle,
        paragraphSpacing: Provider.of<NovelProvider>(context, listen: false).paragraphSpacing,
      );
      if (!mounted) return;

      // 创建新的页面控制器
      _pageController?.dispose();
      _pageController = PageController(initialPage: targetPage);
      setState(() {
        _currentPageIndex = targetPage;
        _currentChapterIndex = chapterIndex;
        _ready = true;
      });
      // 保存阅读进度
      _persistProgress();
    } finally {
      _jumpingChapter = false;
    }
  }

  /// 保存当前阅读进度
  void _persistProgress() {
    if (!_ready) return;
    // 获取当前页面的引用信息
    final ref = widget.controller.pageRefAt(_currentPageIndex);
    try {
      // 获取当前小说信息
      final novel = _novelProvider.getNovelById(widget.novelId);

      // 获取当前章节索引和标题
      final chapterIndex = widget.controller.chapterIndexAtOffset(ref.pageStartOffset);
      final chapterTitle = widget.controller.chapterTitleAtIndex(chapterIndex);

      _currentChapterIndex = chapterIndex;

      // 更新小说阅读进度
      _novelProvider.updateNovelProgress(
        novel.copyWith(
          currentPageIndex: _currentPageIndex,
          currentChapter: chapterIndex,
          lastChapterTitle: chapterTitle.isNotEmpty ? chapterTitle : novel.lastChapterTitle,
          durChapterIndex: ref.segmentIndex,
          durChapterPage: ref.pageInSegment,
          durChapterPos: ref.pageStartOffset,
        ),
      );
    } catch (_) {
      // 忽略保存进度时的错误
    }
  }

  @override
  void initState() {
    super.initState();
    // 获取小说状态管理提供者
    _novelProvider = Provider.of<NovelProvider>(context, listen: false);

    // 绑定音量键监听通道
    if (!_volumeChannelBound) {
      _volumeChannel.setMethodCallHandler((call) async {
        await _handleVolumeCommand(call.method);
      });
      _volumeChannelBound = true;
    }

    // 进入阅读页面时启用音量键拦截
    VolumeKeyController.setVolumeKeysEnabled(true);

    // 如果指定了起始章节，重置相关索引
    if (widget.startChapterIndex != null) {
      _startSegmentIndex = 0;
      _startPageInSegment = 0;
      _startByteOffset = null;
      _currentPageIndex = 0;
      return;
    }

    // 加载保存的阅读进度
    try {
      final novel = _novelProvider.getNovelById(widget.novelId);
      if (novel.durChapterPos != null) {
        _startByteOffset = novel.durChapterPos;
      }

      if (novel.durChapterIndex != null) {
        _startSegmentIndex = novel.durChapterIndex!;
      }
      if (novel.durChapterPage != null) {
        _startPageInSegment = novel.durChapterPage!;
      }

      if ((novel.durChapterIndex == null || novel.durChapterPage == null) &&
          _startByteOffset == null &&
          novel.currentPageIndex != null &&
          novel.currentPageIndex! > 0) {
        _currentPageIndex = novel.currentPageIndex!;
      }
    } catch (_) {
      // 忽略加载进度时的错误
    }
  }

  @override
  void dispose() {
    // 取消防抖定时器
    _rePaginateDebounce?.cancel();
    // 保存当前进度
    _persistProgress();
    // 释放页面控制器
    _pageController?.dispose();
    
    // 离开阅读页面时禁用音量键拦截
    VolumeKeyController.setVolumeKeysEnabled(false);
    
    super.dispose();
  }

  /// 构建阅读器的文本样式
  TextStyle _buildReaderTextStyle(NovelProvider novelProvider) {
    // 如果设置了自定义字体，则使用自定义字体
    if (novelProvider.customFontPath != null &&
        novelProvider.customFontPath!.isNotEmpty) {
      return TextStyle(
        fontSize: novelProvider.readerFontSize, // 字体大小
        fontFamily: 'CustomFont', // 自定义字体名称
        fontWeight: novelProvider.fontWeight, // 字体粗细
        letterSpacing: novelProvider.letterSpacing, // 字间距
        height: novelProvider.lineSpacing, // 行高
        color: Colors.black, // 字体颜色
      );
    }
    // 使用系统字体
    return TextStyle(
      fontSize: novelProvider.readerFontSize,
      fontFamily: novelProvider.fontFamily,
      fontWeight: novelProvider.fontWeight,
      letterSpacing: novelProvider.letterSpacing,
      height: novelProvider.lineSpacing,
      color: Colors.black,
    );
  }

  /// 计算内容区域大小（减去内边距）
  Size _contentSize(BoxConstraints c, NovelProvider novelProvider) {
    final w = (c.maxWidth - novelProvider.readerPaddingLeft - novelProvider.readerPaddingRight)
        .clamp(0.0, c.maxWidth);
    final h = (c.maxHeight - novelProvider.readerPaddingTop - novelProvider.readerPaddingBottom)
        .clamp(0.0, c.maxHeight);
    return Size(w, h);
  }

  /// 生成排版配置的唯一标识，用于检测排版变化
  String _typographyKey(NovelProvider novelProvider, Size contentSize) {
    return [
      novelProvider.readerFontSize, // 字体大小
      novelProvider.fontWeight.index, // 字体粗细索引
      novelProvider.letterSpacing, // 字间距
      novelProvider.lineSpacing, // 行高
      novelProvider.paragraphSpacing, // 段落间距
      novelProvider.readerPaddingTop, // 顶部内边距
      novelProvider.readerPaddingBottom, // 底部内边距
      novelProvider.readerPaddingLeft, // 左侧内边距
      novelProvider.readerPaddingRight, // 右侧内边距
      novelProvider.fontFamily, // 字体家族
      novelProvider.customFontPath ?? '', // 自定义字体路径
      contentSize.width, // 内容宽度
      contentSize.height, // 内容高度
    ].join('|');
  }

  /// 调度重新分页（防抖处理）
  void _scheduleRepaginate(NovelProvider novelProvider, BoxConstraints c, TextStyle textStyle) {
    final contentSize = _contentSize(c, novelProvider);
    final key = _typographyKey(novelProvider, contentSize);
    // 如果是首次设置排版标识，直接返回
    if (_lastTypographyKey == null) {
      _lastTypographyKey = key;
      return;
    }
    // 如果排版配置未变化，无需重新分页
    if (_lastTypographyKey == key) return;
    _lastTypographyKey = key;

    if (!_ready) return;
    // 取消之前的防抖定时器
    _rePaginateDebounce?.cancel();
    // 设置新的防抖定时器（200ms后执行）
    _rePaginateDebounce = Timer(const Duration(milliseconds: 200), () async {
      if (!mounted) return;
      final layoutSize = _lastLayoutSize;
      final lastStyle = _lastTextStyle;
      if (layoutSize == null || lastStyle == null) return;

      // 获取当前阅读位置
      final currentOffset = widget.controller.pageRefAt(_currentPageIndex).pageStartOffset;
      // 跳转到相同位置，但使用新的排版配置
      final targetPage = await widget.controller.jumpToByteOffset(
        currentOffset,
        contentSize,
        textStyle,
        paragraphSpacing: novelProvider.paragraphSpacing,
      );
      if (!mounted) return;
      // 释放旧的页面控制器
      _pageController?.dispose();
      // 创建新的页面控制器
      _pageController = PageController(initialPage: targetPage);
      setState(() {
        _currentPageIndex = targetPage;
      });
    });
  }

  /// 加载自定义字体
  Future<void> _loadCustomFont(String fontPath) async {
    // 如果字体路径未变化，无需重新加载
    if (fontPath == _lastCustomFontPath) return;
    
    try {
      // 创建字体加载器
      final fontLoader = FontLoader('CustomFont');
      // 从文件加载字体数据
      fontLoader.addFont(File(fontPath).readAsBytes().then((bytes) => ByteData.view(bytes.buffer)));
      // 加载字体
      await fontLoader.load();
      _lastCustomFontPath = fontPath;
      debugPrint('Custom font loaded successfully');
    } catch (e) {
      debugPrint('Error loading custom font file: $e');
      _lastCustomFontPath = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // 监听自定义字体路径变化，只在变化时加载
    final novelProvider = Provider.of<NovelProvider>(context);
    if (novelProvider.customFontPath != null && novelProvider.customFontPath!.isNotEmpty) {
      _loadCustomFont(novelProvider.customFontPath!);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取当前小说信息
    final novel = _novelProvider.getNovelById(widget.novelId);

    return StatusBarStyle(
      data: const StatusBarStyleData(backgroundColor: Colors.transparent), // 设置状态栏透明
      child: Scaffold(
        body: WillPopScope(
          // 拦截系统返回手势和返回按钮
          onWillPop: () async {
            if (_showCatalogOverlay) {
              // 隐藏目录弹窗
              _updateOverlayState(showCatalog: false);
              return false; // 拦截返回
            } else if (_showSettingsOverlay) {
              // 隐藏设置弹窗
              _updateOverlayState(showSettings: false);
              return false; // 拦截返回
            } else if (_showUIOverlay) {
              // 隐藏UI弹窗
              _updateOverlayState(showUI: false);
              return false; // 拦截返回
            }
            // 如果没有弹窗显示，则正常返回
            // 在返回前禁用音量键拦截
            VolumeKeyController.setVolumeKeysEnabled(false);
            return true;
          },
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (ctx, c) {
                  // 获取小说状态管理
                  final novelProvider = Provider.of<NovelProvider>(context);
                  // 构建文本样式
                  final textStyle = _buildReaderTextStyle(novelProvider);
                  // 计算内容区域大小
                  final contentSize = _contentSize(c, novelProvider);
                  // 保存布局信息
                  _lastLayoutSize = c.biggest;
                  _lastContentSize = contentSize;
                  _lastTextStyle = textStyle;
                  // 检查是否需要重新分页
                  _scheduleRepaginate(novelProvider, c, textStyle);
                  
                  // 如果内容未准备就绪，显示加载指示器
                  if (!_ready) {
                    // 初始化阅读内容
                    if (!_initializing && !_jumpingChapter) {
                      _initializing = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        Future<void>(() async {
                          if (!mounted) return;
                          if (widget.startChapterIndex != null) {
                            // 如果指定了起始章节，跳转到该章节
                            await _jumpToChapter(widget.startChapterIndex!);
                          } else if (_startByteOffset != null) {
                            final targetPage = await widget.controller.jumpToByteOffset(
                              _startByteOffset!,
                              contentSize,
                              textStyle,
                              paragraphSpacing: novelProvider.paragraphSpacing,
                            );
                            if (!mounted) return;
                            _pageController?.dispose();
                            _pageController = PageController(initialPage: targetPage);
                            setState(() {
                              _currentPageIndex = targetPage;
                              _currentChapterIndex = widget.controller.chapterIndexAtOffset(
                                widget.controller.pageRefAt(targetPage).pageStartOffset,
                              );
                              _ready = true;
                            });
                          } else {
                            // 加载初始阅读内容
                            await widget.controller.loadInitial(
                              contentSize,
                              textStyle,
                              startSegmentIndex: _startSegmentIndex,
                              startPageInSegment: _startPageInSegment,
                              paragraphSpacing: novelProvider.paragraphSpacing,
                            );
                            if (!mounted) return;
                            // 计算起始页码
                            final jumpTo = novelStartPage(widget.controller, _currentPageIndex);
                            // 创建页面控制器
                            _pageController?.dispose();
                            _pageController = PageController(initialPage: jumpTo);
                            setState(() {
                              _currentPageIndex = jumpTo;
                              _currentChapterIndex = widget.controller.chapterIndexAtOffset(
                                widget.controller.pageRefAt(jumpTo).pageStartOffset,
                              );
                              _ready = true;
                            });
                          }
                        }).whenComplete(() {
                          if (mounted) {
                            _initializing = false;
                          }
                        });
                      });
                    }
                    return const Center(child: CircularProgressIndicator());
                  }

                  return Consumer<NovelProvider>(
                    builder: (context, novelProvider, child) {
                      final textStyle = _buildReaderTextStyle(novelProvider);

                      return AnimatedBuilder(
                        animation: widget.controller,
                        builder: (context, _) {
                          final pageController = _pageController ??= PageController(
                            initialPage: novelStartPage(widget.controller, _currentPageIndex),
                          );

                          return GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              _updateOverlayState(showUI: !_showUIOverlay);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: novelProvider.readerBackgroundImage == null
                                    ? novelProvider.readerBackgroundColor
                                    : null,
                                image: novelProvider.readerBackgroundImage != null
                                    ? DecorationImage(
                                        image: novelProvider.readerBackgroundImage!.startsWith('assets/')
                                            ? AssetImage(novelProvider.readerBackgroundImage!)
                                            : FileImage(File(novelProvider.readerBackgroundImage!)),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: PageView.builder(
                                controller: pageController,
                                itemCount: widget.controller.pages.length,
                                physics: _getPageViewPhysics(novelProvider.readerTurnAnimation),
                                onPageChanged: (index) {
                                  final contentSize = _contentSize(c, novelProvider);
                                  widget.controller.ensureMoreIfNeeded(
                                    index,
                                    contentSize,
                                    textStyle,
                                    paragraphSpacing: novelProvider.paragraphSpacing,
                                  );

                                  setState(() {
                                    _currentPageIndex = index;
                                    _currentChapterIndex = widget.controller.chapterIndexAtOffset(
                                      widget.controller.pageRefAt(index).pageStartOffset,
                                    );
                                  });

                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (!mounted) return;
                                    _persistProgress();
                                  });
                                },
                                itemBuilder: (_, i) {
                                  final page = Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      novelProvider.readerPaddingLeft,
                                      novelProvider.readerPaddingTop,
                                      novelProvider.readerPaddingRight,
                                      novelProvider.readerPaddingBottom,
                                    ),
                                    child: Text(
                                      widget.controller.pages[i].join('\n'),
                                      style: textStyle,
                                    ),
                                  );

                                  return ReaderTurnEffects.wrap(
                                    animationName: novelProvider.readerTurnAnimation,
                                    controller: pageController,
                                    index: i,
                                    child: page,
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
              // UI弹窗组件
              if (_showUIOverlay && _ready)
                ReaderUIOverlay(
                  novelTitle: novel.title, // 小说标题
                  currentPage: _currentPageIndex + 1, // 当前页码（从1开始显示）
                  totalPages: widget.controller.pages.length, // 总页数
                  onBack: () {
                    // 返回上一页
                    Navigator.pop(context);
                  },
                  onCatalog: () {
                    _updateOverlayState(showUI: false);
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      await widget.controller.ensureChapterIndexLoaded();
                      if (!mounted) return;
                      final ref = widget.controller.pageRefAt(_currentPageIndex);
                      setState(() {
                        _currentChapterIndex = widget.controller.chapterIndexAtOffset(ref.pageStartOffset);
                      });
                      await _updateOverlayState(showCatalog: true);
                    });
                  },
                  onReadAloud: () {
                    // 朗读功能（待实现）
                    _updateOverlayState(showUI: false);
                    print('朗读按钮点击');
                    // TODO: 实现朗读功能
                  },
                  onInterface: () {
                    // 显示设置
                    _updateOverlayState(showUI: false, showSettings: true);
                  },
                  onClose: () {
                    // 关闭弹窗
                    debugPrint('关闭按钮点击');
                    _updateOverlayState(showUI: false);
                  },
                ),
              // 目录弹窗组件
              if (_showCatalogOverlay && _ready)
                ReaderCatalogOverlay(
                  novelTitle: novel.title,
                  currentChapterIndex: _currentChapterIndex, // 当前章节索引
                  totalChapters: widget.controller.totalChapters, // 总章节数
                  chapterTitles: widget.controller.chapterTitles, // 章节标题列表
                  onBack: () {
                    // 隐藏目录
                    _updateOverlayState(showCatalog: false);
                  },
                  onChapterSelect: (index) {
                    // 选择章节
                    _updateOverlayState(showCatalog: false);
                    _jumpToChapter(index);
                  },
                ),
              // 设置弹窗组件
              if (_showSettingsOverlay && _ready)
                ReaderSettingsOverlay(
                  onBack: () {
                    // 隐藏设置
                    _updateOverlayState(showSettings: false);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 根据翻页动画类型获取对应的动画曲线
  Curve _getAnimationCurve(String animationName) {
    switch (animationName) {
      case '左右翻页':
        return Curves.easeOutCubic;
      case '覆盖翻页':
        return Curves.easeInOut;
      case '仿真翻页':
        return Curves.linearToEaseOut;
      default:
        return Curves.easeOut;
    }
  }

  /// 根据翻页动画类型获取对应的PageView物理属性
  ScrollPhysics _getPageViewPhysics(String animationName) {
    switch (animationName) {
      case '左右翻页':
        return const PageScrollPhysics();
      case '覆盖翻页':
        return const ClampingScrollPhysics();
      case '仿真翻页':
        return const BouncingScrollPhysics();
      default:
        return const PageScrollPhysics();
    }
  }

  /// 更新overlay显示状态并相应地控制音量键拦截
  Future<void> _updateOverlayState({
    bool? showUI,
    bool? showCatalog,
    bool? showSettings,
  }) async {
    bool shouldInterceptVolume = true;
    
    // 更新弹窗显示状态
    if (showUI != null) _showUIOverlay = showUI;
    if (showCatalog != null) _showCatalogOverlay = showCatalog;
    if (showSettings != null) _showSettingsOverlay = showSettings;
    
    // 如果有任何overlay显示，则不拦截音量键
    if (_showUIOverlay || _showCatalogOverlay || _showSettingsOverlay) {
      shouldInterceptVolume = false;
    }
    
    // 更新音量键拦截状态
    await VolumeKeyController.updateVolumeKeyStatus(shouldIntercept: shouldInterceptVolume);
    // 重新构建UI
    setState(() {});
  }
  
  /// 确定小说的起始页码
  int novelStartPage(ReaderController controller, int fallbackPage) {
    // 如果控制器指定了初始全局页码，则使用该页码
    if (controller.initialGlobalPage > 0) return controller.initialGlobalPage;
    // 否则使用备用页码
    if (controller.pages.isEmpty) return 0;
    return fallbackPage.clamp(0, controller.pages.length - 1);
  }
}