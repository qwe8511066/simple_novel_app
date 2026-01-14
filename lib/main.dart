import 'package:app/pages/reader/reader_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/novel_provider.dart';
import 'pages/tabs_screen.dart';
import 'pages/reader/reader_page.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'utils/smoothSlideTransitionBuilder.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => NovelProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // 获取小说文件路径
  Future<String> _getNovelFilePath(String novelId) async {
    final dir = await getApplicationDocumentsDirectory();
    final novelDir = Directory('${dir.path}/novels');
    return '${novelDir.path}/$novelId';
  }

  @override
  void initState() {
    super.initState();

    // 应用启动时加载本地小说
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<NovelProvider>(context, listen: false).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NovelProvider>(
      builder: (context, provider, child) {
        return MaterialApp(
          title: '简单小说',
          theme: ThemeData(
            pageTransitionsTheme: PageTransitionsTheme(
              builders: {
                TargetPlatform.android: SmoothSlideTransitionBuilder(),
                TargetPlatform.iOS: SmoothSlideTransitionBuilder(),
              },
            ),
            useMaterial3: true,
            brightness: Brightness.light,
            primaryColor: provider.themeColor,
            textTheme: ThemeData.light().textTheme.copyWith(
              bodyLarge: TextStyle(
                fontSize: provider.fontSize.toDouble(),
                color: Colors.black87,
              ),
              bodyMedium: TextStyle(
                fontSize: (provider.fontSize - 2).toDouble(),
                color: Colors.black87,
              ),
              bodySmall: TextStyle(
                fontSize: (provider.fontSize - 4).toDouble(),
                color: Colors.black54,
              ),
              titleLarge: TextStyle(
                fontSize: (provider.fontSize + 8).toDouble(),
                color: provider.themeColor,
              ),
              titleMedium: TextStyle(
                fontSize: (provider.fontSize + 4).toDouble(),
                color: provider.themeColor,
              ),
              titleSmall: TextStyle(
                fontSize: (provider.fontSize).toDouble(),
                color: provider.themeColor,
              ),
              headlineSmall: TextStyle(
                fontSize: (provider.fontSize + 6).toDouble(),
                color: provider.themeColor,
              ),
            ),
            iconTheme: IconThemeData(color: provider.themeColor),
          ),
          themeMode: ThemeMode.light,
          home: const TabsScreen(),
          routes: {
            '/reader': (context) {
              final args =
                  ModalRoute.of(context)!.settings.arguments
                      as Map<String, dynamic>;
              final novelId = args['novelId'] as String;
              final novelTitle = args['novelTitle'] as String?;

              return FutureBuilder<String>(
                future: _getNovelFilePath(novelId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError || snapshot.data == null) {
                    return const Center(child: Text('无法加载小说'));
                  }

                  final file = File(snapshot.data!);
                  final controller = ReaderController(
                    file,
                    novelTitle: novelTitle,
                  );

                  return ReaderPage(controller: controller, novelId: novelId);
                },
              );
            },
          },
        );
      },
    );
  }
}
