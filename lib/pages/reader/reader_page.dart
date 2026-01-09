// reader_page.dart
import 'package:flutter/material.dart';
import 'reader_controller.dart';

class ReaderPage extends StatefulWidget {
  final ReaderController controller;

  const ReaderPage({super.key, required this.controller});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();

    widget.controller.loadInitial().then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final size = MediaQuery.of(context).size;
        widget.controller.repaginate(
          Size(size.width, size.height),
          const TextStyle(fontSize: 18, height: 1.6),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (_, __) {
        if (!widget.controller.pageReady) {
          return const Center(child: CircularProgressIndicator());
        }

        return PageView.builder(
          controller: _pageController,
          itemCount: widget.controller.pageCount,
          onPageChanged: (index) {
            // 可在这里判断是否需要 loadMore
          },
          itemBuilder: (_, index) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.controller.pageText(index),
                style: const TextStyle(fontSize: 18, height: 1.6),
              ),
            );
          },
        );
      },
    );
  }
}
