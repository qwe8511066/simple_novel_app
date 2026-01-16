import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'reader_controller.dart';
import '../../providers/novel_provider.dart';
import '../../utils/statusBarStyle.dart';
import './reader_settings/reader_ui_overlay.dart';
import './reader_settings/reader_catalog_overlay.dart';
import './reader_settings/reader_settings_overlay.dart';
import 'package:flutter/services.dart';
class ReaderPage extends StatefulWidget {
  final ReaderController controller;
  final String novelId;
  final int? startChapterIndex;

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
  bool _ready = false;
  int _currentPageIndex = 0;
  PageController? _pageController;
  int _startSegmentIndex = 0;
  int _startPageInSegment = 0;
  bool _initializing = false;
  bool _jumpingChapter = false;
  int _currentChapterIndex = 0;
  
  bool _showUIOverlay = false; // 是否显示UI弹窗，默认显示以方便用户操作
  bool _showCatalogOverlay = false; // 是否显示目录弹窗
  bool _showSettingsOverlay = false; // 是否显示设置弹窗

  late final NovelProvider _novelProvider;

  Size? _lastLayoutSize;
  Size? _lastContentSize;
  TextStyle? _lastTextStyle;

  Timer? _rePaginateDebounce;
  String? _lastTypographyKey;

  Future<void> _jumpToChapter(int chapterIndex) async {
    final layoutSize = _lastContentSize;
    final textStyle = _lastTextStyle;
    if (layoutSize == null || textStyle == null) return;

    await widget.controller.ensureChapterIndexLoaded();

    if (_jumpingChapter) return;
    _jumpingChapter = true;

    try {
      setState(() {
        _ready = false;
      });
      _pageController?.dispose();
      _pageController = null;

      final byteOffset = widget.controller.chapterStartOffsetAt(chapterIndex);
      final targetPage = await widget.controller.jumpToByteOffset(
        byteOffset,
        layoutSize,
        textStyle,
        paragraphSpacing: Provider.of<NovelProvider>(context, listen: false).paragraphSpacing,
      );
      if (!mounted) return;

      _pageController?.dispose();
      _pageController = PageController(initialPage: targetPage);
      setState(() {
        _currentPageIndex = targetPage;
        _currentChapterIndex = chapterIndex;
        _ready = true;
      });
      _persistProgress();
    } finally {
      _jumpingChapter = false;
    }
  }

  void _persistProgress() {
    if (!_ready) return;
    final ref = widget.controller.pageRefAt(_currentPageIndex);
    try {
      final novel = _novelProvider.getNovelById(widget.novelId);

      final chapterIndex = widget.controller.chapterIndexAtOffset(ref.pageStartOffset);
      final chapterTitle = widget.controller.chapterTitleAtIndex(chapterIndex);

      _currentChapterIndex = chapterIndex;

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
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _novelProvider = Provider.of<NovelProvider>(context, listen: false);

    if (widget.startChapterIndex != null) {
      _startSegmentIndex = 0;
      _startPageInSegment = 0;
      _currentPageIndex = 0;
      return;
    }

    // 加载保存的阅读进度
    try {
      final novel = _novelProvider.getNovelById(widget.novelId);
      if (novel.durChapterIndex != null) {
        _startSegmentIndex = novel.durChapterIndex!;
      }
      if (novel.durChapterPage != null) {
        _startPageInSegment = novel.durChapterPage!;
      }
      if ((novel.durChapterIndex == null || novel.durChapterPage == null) &&
          novel.currentPageIndex != null &&
          novel.currentPageIndex! > 0) {
        _currentPageIndex = novel.currentPageIndex!;
      }

      if (novel.currentChapter != null) {
        _currentChapterIndex = novel.currentChapter!;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _rePaginateDebounce?.cancel();
    _persistProgress();
    _pageController?.dispose();
    super.dispose();
  }

  TextStyle _buildReaderTextStyle(NovelProvider novelProvider) {
    if (novelProvider.customFontPath != null &&
        novelProvider.customFontPath!.isNotEmpty) {
      return TextStyle(
        fontSize: novelProvider.readerFontSize,
        fontFamily: 'CustomFont',
        fontWeight: novelProvider.fontWeight,
        letterSpacing: novelProvider.letterSpacing,
        height: novelProvider.lineSpacing,
        color: Colors.black,
      );
    }
    return TextStyle(
      fontSize: novelProvider.readerFontSize,
      fontFamily: novelProvider.fontFamily,
      fontWeight: novelProvider.fontWeight,
      letterSpacing: novelProvider.letterSpacing,
      height: novelProvider.lineSpacing,
      color: Colors.black,
    );
  }

  Size _contentSize(BoxConstraints c, NovelProvider novelProvider) {
    final w = (c.maxWidth - novelProvider.readerPaddingLeft - novelProvider.readerPaddingRight)
        .clamp(0.0, c.maxWidth);
    final h = (c.maxHeight - novelProvider.readerPaddingTop - novelProvider.readerPaddingBottom)
        .clamp(0.0, c.maxHeight);
    return Size(w, h);
  }

  String _typographyKey(NovelProvider novelProvider, Size contentSize) {
    return [
      novelProvider.readerFontSize,
      novelProvider.fontWeight.index,
      novelProvider.letterSpacing,
      novelProvider.lineSpacing,
      novelProvider.paragraphSpacing,
      novelProvider.readerPaddingTop,
      novelProvider.readerPaddingBottom,
      novelProvider.readerPaddingLeft,
      novelProvider.readerPaddingRight,
      novelProvider.fontFamily,
      novelProvider.customFontPath ?? '',
      contentSize.width,
      contentSize.height,
    ].join('|');
  }

  void _scheduleRepaginate(NovelProvider novelProvider, BoxConstraints c, TextStyle textStyle) {
    final contentSize = _contentSize(c, novelProvider);
    final key = _typographyKey(novelProvider, contentSize);
    if (_lastTypographyKey == null) {
      _lastTypographyKey = key;
      return;
    }
    if (_lastTypographyKey == key) return;
    _lastTypographyKey = key;

    if (!_ready) return;
    _rePaginateDebounce?.cancel();
    _rePaginateDebounce = Timer(const Duration(milliseconds: 200), () async {
      if (!mounted) return;
      final layoutSize = _lastLayoutSize;
      final lastStyle = _lastTextStyle;
      if (layoutSize == null || lastStyle == null) return;

      final currentOffset = widget.controller.pageRefAt(_currentPageIndex).pageStartOffset;
      final targetPage = await widget.controller.jumpToByteOffset(
        currentOffset,
        contentSize,
        textStyle,
        paragraphSpacing: novelProvider.paragraphSpacing,
      );
      if (!mounted) return;
      _pageController?.dispose();
      _pageController = PageController(initialPage: targetPage);
      setState(() {
        _currentPageIndex = targetPage;
      });
    });
  }

  // 记录上一次的自定义字体路径，避免重复加载
  String? _lastCustomFontPath;
  
  // 加载自定义字体
  Future<void> _loadCustomFont(String fontPath) async {
    if (fontPath == _lastCustomFontPath) return; // 已加载过，跳过
    
    try {
      final fontLoader = FontLoader('CustomFont');
      fontLoader.addFont(File(fontPath).readAsBytes().then((bytes) => ByteData.view(bytes.buffer)));
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
    final novel = _novelProvider.getNovelById(widget.novelId);

    return StatusBarStyle(
      data: const StatusBarStyleData(backgroundColor: Colors.transparent),
      child: Scaffold(
        body: WillPopScope(
          // 拦截系统返回手势和返回按钮
          onWillPop: () async {
            if (_showCatalogOverlay) {
              // 隐藏目录弹窗
              _showCatalogOverlay = false;
              setState(() {});
              return false; // 拦截返回
            } else if (_showSettingsOverlay) {
              // 隐藏设置弹窗
              _showSettingsOverlay = false;
              setState(() {});
              return false; // 拦截返回
            } else if (_showUIOverlay) {
              // 隐藏UI弹窗
              _showUIOverlay = false;
              setState(() {});
              return false; // 拦截返回
            }
            // 如果没有弹窗显示，则正常返回
            return true;
          },
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (ctx, c) {
                  final novelProvider = Provider.of<NovelProvider>(context);
                  final textStyle = _buildReaderTextStyle(novelProvider);
                  final contentSize = _contentSize(c, novelProvider);
                  _lastLayoutSize = c.biggest;
                  _lastContentSize = contentSize;
                  _lastTextStyle = textStyle;
                  _scheduleRepaginate(novelProvider, c, textStyle);
                  if (!_ready) {
                    if (!_initializing && !_jumpingChapter) {
                      _initializing = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        Future<void>(() async {
                          if (!mounted) return;
                          if (widget.startChapterIndex != null) {
                            await _jumpToChapter(widget.startChapterIndex!);
                          } else {
                            await widget.controller.loadInitial(
                              contentSize,
                              textStyle,
                              startSegmentIndex: _startSegmentIndex,
                              startPageInSegment: _startPageInSegment,
                              paragraphSpacing: novelProvider.paragraphSpacing,
                            );
                            if (!mounted) return;
                            final jumpTo = novelStartPage(widget.controller, _currentPageIndex);
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
                      // 根据设置创建文本样式，避免不必要的FontLoader重建
                      final textStyle = _buildReaderTextStyle(novelProvider);
                      
                      return AnimatedBuilder(
                        animation: widget.controller,
                        builder: (context, _) {
                          final pageController = _pageController ??=
                              PageController(initialPage: novelStartPage(widget.controller, _currentPageIndex));

                          return GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              setState(() {
                                _showUIOverlay = !_showUIOverlay;
                              });
                            },
                            child: Container(
                              // 设置背景颜色或图片
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
                                onPageChanged: (index) {
                                  Future<void> handleIndex(int effectiveIndex) async {
                                    final contentSize = _contentSize(c, novelProvider);
                                    widget.controller.ensureMoreIfNeeded(
                                      effectiveIndex,
                                      contentSize,
                                      textStyle,
                                      paragraphSpacing: novelProvider.paragraphSpacing,
                                    );

                                    final ref = widget.controller.pageRefAt(effectiveIndex);
                                    try {
                                      final novel = _novelProvider.getNovelById(widget.novelId);

                                      final chapterIndex = widget.controller.chapterIndexAtOffset(ref.pageStartOffset);
                                      final chapterTitle = widget.controller.chapterTitleAtIndex(chapterIndex);
                                      _novelProvider.updateNovelProgress(
                                        novel.copyWith(
                                          currentPageIndex: effectiveIndex,
                                          currentChapter: chapterIndex,
                                          lastChapterTitle: chapterTitle.isNotEmpty
                                              ? chapterTitle
                                              : novel.lastChapterTitle,
                                          durChapterIndex: ref.segmentIndex,
                                          durChapterPage: ref.pageInSegment,
                                          durChapterPos: ref.pageStartOffset,
                                        ),
                                      );
                                    } catch (_) {}
                                  }

                                  setState(() {
                                    _currentPageIndex = index;
                                    _currentChapterIndex = widget.controller.chapterIndexAtOffset(
                                      widget.controller.pageRefAt(index).pageStartOffset,
                                    );
                                  });

                                  widget.controller
                                      .ensurePreviousIfNeeded(
                                        index,
                                        _contentSize(c, novelProvider),
                                        textStyle,
                                        paragraphSpacing: novelProvider.paragraphSpacing,
                                      )
                                      .then((added) {
                                    if (!mounted) return;

                                    final effectiveIndex = index + added;
                                    if (added > 0) {
                                      final pc = _pageController;
                                      if (pc != null && pc.hasClients) {
                                        pc.jumpToPage(effectiveIndex);
                                      }
                                      setState(() {
                                        _currentPageIndex = effectiveIndex;
                                      });
                                    }

                                    handleIndex(effectiveIndex);
                                  });
                                },
                                itemBuilder: (_, i) {
                                  return Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      novelProvider.readerPaddingLeft,
                                      novelProvider.readerPaddingTop,
                                      novelProvider.readerPaddingRight,
                                      novelProvider.readerPaddingBottom,
                                    ),
                                    child: SingleChildScrollView(
                                      child: Text(
                                        widget.controller.pages[i].join('\n'),
                                        style: textStyle,
                                      ),
                                    ),
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
                  novelTitle: novel.title,
                  currentPage: _currentPageIndex + 1,
                  totalPages: widget.controller.pages.length,
                  onBack: () {
                    // 返回上一页
                    Navigator.pop(context);
                  },
                  onCatalog: () {
                    _showUIOverlay = false;
                    _showCatalogOverlay = true;
                    setState(() {});
                    // 目录按钮点击事件
                    print('目录按钮点击');
                  },
                  onReadAloud: () {
                    _showUIOverlay = false;
                    setState(() {});
                    // 朗读按钮点击事件
                    print('朗读按钮点击');
                    // TODO: 实现朗读功能
                  },
                  onInterface: () {
                    _showUIOverlay = false;
                    _showSettingsOverlay = true;
                    setState(() {});
                    // 界面按钮点击事件
                    print('界面按钮点击');
                  },

                  onClose: () {
                    debugPrint('关闭按钮点击');
                    // 关闭弹窗
                    _showUIOverlay = false;
                    setState(() {});
                  },
                ),
              // 目录弹窗组件
              if (_showCatalogOverlay && _ready)
                ReaderCatalogOverlay(
                  novelTitle: novel.title,
                  currentChapterIndex: _currentChapterIndex,
                  totalChapters: widget.controller.totalChapters,
                  chapterTitles: widget.controller.chapterTitles,
                  onBack: () {
                    _showCatalogOverlay = false;
                    setState(() {});
                  },
                  onChapterSelect: (index) {
                    _showCatalogOverlay = false;
                    setState(() {});
                    _jumpToChapter(index);
                  },
                ),
              // 设置弹窗组件
              if (_showSettingsOverlay && _ready)
                ReaderSettingsOverlay(
                  onBack: () {
                    _showSettingsOverlay = false;
                    setState(() {});
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  int novelStartPage(ReaderController controller, int fallbackPage) {
    if (controller.initialGlobalPage > 0) return controller.initialGlobalPage;
    return fallbackPage;
  }
}
