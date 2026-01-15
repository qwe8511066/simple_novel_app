import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'reader_controller.dart';
import '../../providers/novel_provider.dart';
import '../../utils/statusBarStyle.dart';
import './reader_settings/reader_ui_overlay.dart';
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
  PageController? _pageController;
  int _startSegmentIndex = 0;
  int _startPageInSegment = 0;
  
  bool _showUIOverlay = false; // 是否显示UI弹窗，默认显示以方便用户操作

  late final NovelProvider _novelProvider;

  void _persistProgress() {
    if (!_ready) return;
    final ref = widget.controller.pageRefAt(_currentPageIndex);
    try {
      final novel = _novelProvider.getNovelById(widget.novelId);

      final chapterIndex = widget.controller.chapterIndexAtOffset(ref.pageStartOffset);
      final chapterTitle = widget.controller.chapterTitleAtIndex(chapterIndex);

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
    } catch (_) {}
  }

  @override
  void dispose() {
    _persistProgress();
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = const TextStyle(fontSize: 18, height: 1.8);
    final novel = _novelProvider.getNovelById(widget.novelId);

    return StatusBarStyle(
      data: const StatusBarStyleData(backgroundColor: Colors.transparent),
      child: Scaffold(
        body: Stack(
          children: [
            LayoutBuilder(
              builder: (ctx, c) {
                if (!_ready) {
                  widget.controller
                      .loadInitial(
                        c.biggest,
                        style,
                        startSegmentIndex: _startSegmentIndex,
                        startPageInSegment: _startPageInSegment,
                      )
                      .then((_) {
                    if (mounted) {
                      final jumpTo = novelStartPage(widget.controller, _currentPageIndex);
                      _pageController?.dispose();
                      _pageController = PageController(initialPage: jumpTo);
                      setState(() {
                        _currentPageIndex = jumpTo;
                        _ready = true;
                      });
                    }
                  });
                  return const Center(child: CircularProgressIndicator());
                }

                return AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    final pageController = _pageController ??
                        PageController(initialPage: novelStartPage(widget.controller, _currentPageIndex));

                    return GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        setState(() {
                          _showUIOverlay = !_showUIOverlay;
                        });
                      },
                      child: PageView.builder(
                        controller: pageController,
                        itemCount: widget.controller.pages.length,
                        onPageChanged: (index) {
                          setState(() {
                            _currentPageIndex = index;
                          });

                          widget.controller.ensureMoreIfNeeded(index, c.biggest, style);

                          final ref = widget.controller.pageRefAt(index);
                          try {
                            final novel = _novelProvider.getNovelById(widget.novelId);

                            final chapterIndex = widget.controller.chapterIndexAtOffset(ref.pageStartOffset);
                            final chapterTitle = widget.controller.chapterTitleAtIndex(chapterIndex);
                            _novelProvider.updateNovelProgress(
                              novel.copyWith(
                                currentPageIndex: index,
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
                        },
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.all(16),
                          child: SingleChildScrollView(
                            child: Text(
                              widget.controller.pages[i].join('\n'),
                              style: style,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            // UI弹窗组件
            if (_showUIOverlay && _ready)
              ReaderUIOverlay(
                novelTitle: novel.title ?? '未知标题',
                currentPage: _currentPageIndex + 1,
                totalPages: widget.controller.pages.length,
                onBack: () {
                  // 返回上一页
                  Navigator.pop(context);
                },
                onCatalog: () {
                  _showUIOverlay = false;
                  setState(() {});
                  // 目录按钮点击事件
                  print('目录按钮点击');
                  // TODO: 实现目录功能
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
                  setState(() {});
                  // 界面按钮点击事件
                  print('界面按钮点击');
                  // TODO: 实现界面设置功能
                },
                onSettings: () {
                  _showUIOverlay = false;
                  setState(() {});
                  // 设置按钮点击事件
                  print('设置按钮点击');
                  // TODO: 实现设置功能
                },
                onClose: () {
                  debugPrint('关闭按钮点击');
                  // 关闭弹窗
                  _showUIOverlay = false;
                  setState(() {});
                },
              ),
          ],
        ),
      ),
    );
  }

  int novelStartPage(ReaderController controller, int fallbackPage) {
    if (controller.initialGlobalPage > 0) return controller.initialGlobalPage;
    return fallbackPage;
  }
}
