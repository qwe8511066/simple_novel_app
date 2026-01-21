import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/novel_provider.dart';
import '../utils/statusBarStyle.dart';
import 'book_shelf_page.dart';
import 'settings_page.dart';
import 'tts_test_page.dart';
import '../components/novel_import_button.dart';

/// 底部标签页（书架 + 设置）
class TabsScreen extends StatefulWidget {
  const TabsScreen({super.key});

  @override
  State<TabsScreen> createState() => _TabsScreenState();
}

class _TabsScreenState extends State<TabsScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const BookshelfPage(),
    const SettingsPage(),
    const TtsTestPage(),
  ];

  final List<String> _titles = ['我的书架', '设置', 'TTS'];

  final List<IconData> _icons = [Icons.book, Icons.settings, Icons.record_voice_over];

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<NovelProvider>(context, listen: false);
    Color backgroundColor = provider.themeColor;
    return StatusBarStyle(
      data: StatusBarStyleData(backgroundColor: backgroundColor),
      child: Builder(
        builder: (context) {
          final status = StatusBarScope.of(context);
          return Scaffold(
            appBar: AppBar(
              backgroundColor: status.style.statusBarColor,
              title: Text(_titles[_currentIndex]),
              titleTextStyle: TextStyle(
                color: status.textColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              centerTitle: true,

              /// ⭐ 关键：AppBar 明确使用同一套 style
              systemOverlayStyle: status.style,
              actions: [
                // 只在书架页面显示导入小说按钮
                if (_currentIndex == 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: NovelImportButton(),
                  ),
              ],
            ),
            body: _pages[_currentIndex],
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              selectedItemColor: Theme.of(context).primaryColor,
              unselectedItemColor: Colors.grey,
              showSelectedLabels: true,
              showUnselectedLabels: true,
              type: BottomNavigationBarType.fixed,
              items: List.generate(
                _titles.length,
                (index) => BottomNavigationBarItem(
                  icon: Icon(_icons[index]),
                  label: _titles[index],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
