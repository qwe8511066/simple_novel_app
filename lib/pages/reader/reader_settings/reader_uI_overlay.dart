import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/novel_provider.dart';
import '../../../utils/statusBarStyle.dart';

class ReaderUIOverlay extends StatefulWidget {
  final String novelTitle;
  final int currentPage;
  final int totalPages;
  final bool isReading;
  final VoidCallback onBack;
  final VoidCallback onCatalog;
  final VoidCallback onReadAloud;
  final VoidCallback onInterface;
  final VoidCallback onClose; // 添加关闭回调
  const ReaderUIOverlay({
    super.key,
    required this.novelTitle,
    required this.currentPage,
    required this.totalPages,
    required this.isReading,
    required this.onBack,
    required this.onCatalog,
    required this.onReadAloud,
    required this.onInterface,
    required this.onClose, // 添加关闭回调参数
  });

  @override
  State<ReaderUIOverlay> createState() => _ReaderUIOverlayState();
}

class _ReaderUIOverlayState extends State<ReaderUIOverlay> {
  @override
  Widget build(BuildContext context) {
    final novelProvider = Provider.of<NovelProvider>(context);
    final themeColor = novelProvider.themeColor;
    final double statusBarHeight = StatusBarScope.of(context).statusBarHeight;

    final readIcon = widget.isReading ? Icons.stop : Icons.volume_up;
    final readLabel = widget.isReading ? '停止' : '朗读';

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 中间内容区域的点击事件，用于关闭弹窗
          GestureDetector(
            // 捕获空白处点击事件，关闭弹窗
            onTap: widget.onClose,
            child: Container(
              color: Colors.transparent,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          // 顶部状态栏和标题栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              // 阻止事件冒泡，点击顶部状态栏不会关闭UI弹窗
              onTap: () {
                debugPrint('点击了顶部状态栏');
              },
              child: Container(
                color: themeColor,
                child: AppBar(
                  title: Text(
                    widget.novelTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: themeColor,
                  elevation: 0,
                  titleTextStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: widget.onBack,
                  ),
                ),
              ),
            ),
          ),
          // 底部操作栏
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              // 阻止事件冒泡，点击底部操作栏不会关闭UI弹窗
              onTap: () {
                debugPrint('点击了底部操作栏');
              },
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    // 操作按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // 目录
                        GestureDetector(
                          onTap: null,
                          child: Column(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.menu_book,
                                  color: Colors.white,
                                ),
                                onPressed: widget.onCatalog,
                              ),
                              const Text(
                                '目录',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 朗读
                        GestureDetector(
                          onTap: null,
                          child: Column(
                            children: [
                              IconButton(
                                icon: Icon(readIcon, color: Colors.white),
                                onPressed: widget.onReadAloud,
                              ),
                              Text(
                                readLabel,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 界面
                        GestureDetector(
                          onTap: null,
                          child: Column(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.format_color_fill,
                                  color: Colors.white,
                                ),
                                onPressed: widget.onInterface,
                              ),
                              const Text(
                                '界面',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
