import 'dart:io';
import 'package:flutter/material.dart';
import 'pagination_engine.dart';

class ReaderController extends ChangeNotifier {
  final File utf8File;
  List<List<String>> pages = [];

  ReaderController(this.utf8File);

  Future<void> load(Size size, TextStyle style) async {
    final lines = await utf8File.readAsLines();
    final engine = PaginationEngine(lines, style, size);
    pages = engine.paginate();
    notifyListeners();
  }
}
