import 'package:flutter/material.dart';
import 'reader_controller.dart';

class ReaderPage extends StatefulWidget {
  final ReaderController controller;
  const ReaderPage({super.key, required this.controller});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    final style = const TextStyle(fontSize: 18, height: 1.8);

    return Scaffold(
      body: LayoutBuilder(
        builder: (ctx, c) {
          if (!_ready) {
            widget.controller
                .load(c.biggest, style)
                .then((_) => setState(() => _ready = true));
            return const Center(child: CircularProgressIndicator());
          }

          return PageView.builder(
            itemCount: widget.controller.pages.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.controller.pages[i].join('\n'),
                style: style,
              ),
            ),
          );
        },
      ),
    );
  }
}
