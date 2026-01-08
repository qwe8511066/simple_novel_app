import 'package:flutter/material.dart';
import 'book_shelf_page.dart';
import 'settings_page.dart';
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
  ];

  final List<String> _titles = [
    '我的书架',
    '设置',
  ];

  final List<IconData> _icons = [
    Icons.book,
    Icons.settings,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        centerTitle: true,
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
  }
}
