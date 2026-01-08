import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/novel_provider.dart';
import 'pages/tabs_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => NovelProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '简单小说',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const TabsScreen(),
    );
  }
}
