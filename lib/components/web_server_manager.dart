import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_static/shelf_static.dart';

class WebServerManager with WidgetsBindingObserver {
  static final WebServerManager _instance = WebServerManager._internal();
  factory WebServerManager() => _instance;
  WebServerManager._internal();

  HttpServer? _server;
  bool _starting = false;

  static const int port = 8080;

  /// 启动 Web Server
  Future<void> start(String serveDir) async {
    if (_starting) return;
    _starting = true;

    // 1️⃣ 确保旧端口释放
    await stop();

    // 2️⃣ Android 14 必须 delay
    await Future.delayed(const Duration(milliseconds: 600));

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(
          createStaticHandler(
            serveDir,
            listDirectories: true,
          ),
        );

    _server = await serve(
      handler,
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );

    debugPrint(
      'WebServer started at http://${_server!.address.address}:$port',
    );

    _starting = false;
  }

  /// 停止 Web Server
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }
  }

  /// 生命周期感知（关键）
  void attach() {
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      stop();
    }
  }
}
