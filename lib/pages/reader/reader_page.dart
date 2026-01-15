import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'reader_controller.dart';
import '../../providers/novel_provider.dart';
import '../../utils/statusBarStyle.dart';

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
  int _startSegmentIndex = 0;
  int _startPageInSegment = 0;
  late final NovelProvider _novelProvider;

  void _persistProgress() {
    if (!_ready) return;
    final ref = widget.controller.pageRefAt(_currentPageIndex);
    try {
      final novel = _novelProvider.getNovelById(widget.novelId);
      _novelProvider.updateNovelProgress(
        novel.copyWith(
          currentPageIndex: _currentPageIndex,
          durChapterIndex: ref.segmentIndex,
          durChapterPage: ref.pageInSegment,
          durChapterPos: ref.segmentStartOffset,
        ),
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

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
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = const TextStyle(fontSize: 18, height: 1.8);

    return StatusBarStyle(
      data: const StatusBarStyleData(backgroundColor: Colors.transparent),
      child: Scaffold(
        body: LayoutBuilder(
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
                  setState(() => _ready = true);
                  // 加载完成后跳转到保存的页码
                  final jumpTo = novelStartPage(widget.controller, _currentPageIndex);
                  if (jumpTo < widget.controller.pages.length) {
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (mounted) {
                        _pageController.jumpToPage(jumpTo);
                      }
                    });
                  }
                }
              });
              return const Center(child: CircularProgressIndicator());
            }

            return AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                return PageView.builder(
                  controller: _pageController,
                  itemCount: widget.controller.pages.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPageIndex = index;
                    });

                    widget.controller.ensureMoreIfNeeded(index, c.biggest, style);

                    final ref = widget.controller.pageRefAt(index);
                    final novelProvider =
                        Provider.of<NovelProvider>(context, listen: false);
                    try {
                      final novel = novelProvider.getNovelById(widget.novelId);
                      novelProvider.updateNovelProgress(
                        novel.copyWith(
                          currentPageIndex: index,
                          durChapterIndex: ref.segmentIndex,
                          durChapterPage: ref.pageInSegment,
                          durChapterPos: ref.segmentStartOffset,
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
                );
              },
            );
          },
        ),
      ),
    );
  }

  int novelStartPage(ReaderController controller, int fallbackPage) {
    if (controller.initialGlobalPage > 0) return controller.initialGlobalPage;
    return fallbackPage;
  }
}
