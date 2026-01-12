import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/novel_provider.dart';
import '../../../utils/statusBarStyle.dart';

class ReaderUIOverlay extends StatelessWidget {
  final String novelTitle;
  final int currentPage;
  final int totalPages;
  final VoidCallback onBack;
  final VoidCallback onCatalog;
  final VoidCallback onReadAloud;
  final VoidCallback onInterface;
  final VoidCallback onSettings;
  const ReaderUIOverlay({
    super.key,
    required this.novelTitle,
    required this.currentPage,
    required this.totalPages,
    required this.onBack,
    required this.onCatalog,
    required this.onReadAloud,
    required this.onInterface,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final novelProvider = Provider.of<NovelProvider>(context);
    final themeColor = novelProvider.themeColor;
    final double statusBarHeight = StatusBarScope.of(context).statusBarHeight;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 顶部状态栏和标题栏
          Positioned(
            top: statusBarHeight,
            left: 0,
            right: 0,
            child: Container(
              color: themeColor,
              child: AppBar(
                title: Text(
                  statusBarHeight.toString() + novelTitle,
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
                // actions: [
                //   Center(
                //     child: Padding(
                //       padding: const EdgeInsets.only(right: 16),
                //       child: Text(
                //         '第 $currentPage/$totalPages 页',
                //         style: const TextStyle(fontSize: 14, color: Colors.white),
                //       ),
                //     ),
                //   ),
                // ],
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: onBack,
                ),
              ),
            ),
          ),
          // 底部操作栏
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
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
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.menu_book,
                              color: Colors.white,
                            ),
                            onPressed: onCatalog,
                          ),
                          const Text(
                            '目录',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                      // 朗读
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.volume_up,
                              color: Colors.white,
                            ),
                            onPressed: onReadAloud,
                          ),
                          const Text(
                            '朗读',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                      // 界面
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.format_color_fill,
                              color: Colors.white,
                            ),
                            onPressed: onInterface,
                          ),
                          const Text(
                            '界面',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                      // 设置
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.settings,
                              color: Colors.white,
                            ),
                            onPressed: onSettings,
                          ),
                          const Text(
                            '设置',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
