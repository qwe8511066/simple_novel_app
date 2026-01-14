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
              widget.controller.load(c.biggest, style).then((_) {
                if (mounted) {
                  setState(() => _ready = true);
                  // 加载完成后跳转到保存的页码
                  if (_currentPageIndex < widget.controller.pages.length) {
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (mounted) {
                        _pageController.jumpToPage(_currentPageIndex);
                      }
                    });
                  }
                }
              });
              return const Center(child: CircularProgressIndicator());
            }

            return PageView.builder(
              controller: _pageController,
              itemCount: widget.controller.pages.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPageIndex = index;
                });
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
        ),
      ),
    );
  }
}
