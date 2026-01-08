import 'dart:convert';
import 'dart:io';

import 'package:charset_converter/charset_converter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../models/novel.dart';
import '../providers/novel_provider.dart';

/// ===============================
/// Web 小说导入按钮（成品版）
/// ===============================
class WebServiceButton extends StatefulWidget {
  const WebServiceButton({super.key});

  @override
  State<WebServiceButton> createState() => _WebServiceButtonState();
}

class _WebServiceButtonState extends State<WebServiceButton> {
  HttpServer? _server;
  bool _isRunning = false;
  String _serverUrl = '';
  String? _novelDirPath;

  /// ===============================
  /// 初始化小说目录（只做一次）
  /// ===============================
  Future<bool> _ensureNovelDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('novel_dir_path');

    if (savedPath != null && Directory(savedPath).existsSync()) {
      _novelDirPath = savedPath;
      return true;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final novelDir = Directory('${appDir.path}/novels');

    if (!novelDir.existsSync()) {
      await novelDir.create(recursive: true);
    }

    await prefs.setString('novel_dir_path', novelDir.path);
    _novelDirPath = novelDir.path;
    return true;
  }

  /// ===============================
  /// 获取局域网 IP
  /// ===============================
  Future<String> _getLocalIp() async {
    try {
      // 获取所有激活的网络接口
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      
      // 定义优先检查的接口名称关键词
      final preferredInterfaces = ['wlan', 'wi-fi', 'eth', 'en', 'lo'];
      
      // 首先尝试查找WiFi或以太网接口
      for (var keyword in preferredInterfaces) {
        for (var interface in interfaces) {
          if (interface.name.toLowerCase().contains(keyword)) {
            for (var addr in interface.addresses) {
              if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
                // 确保是局域网地址（10.x.x.x, 172.16.x.x-172.31.x.x, 192.168.x.x）
                if (addr.address.startsWith('10.') ||
                    addr.address.startsWith('172.') ||
                    addr.address.startsWith('192.168.')) {
                  print('Found preferred IP address: ${addr.address} on interface ${interface.name}');
                  return addr.address;
                }
              }
            }
          }
        }
      }
      
      // 如果没有找到符合条件的地址，返回所有非回环IPv4地址供调试
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            print('Using fallback IP address: ${addr.address} on interface ${interface.name}');
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('Error getting local IP: $e');
      // 如果出现错误，返回127.0.0.1
    }
    print('Failed to get valid IP address, using 127.0.0.1');
    return '127.0.0.1';
  }

  /// ===============================
  /// 处理上传请求
  /// ===============================
  Future<Response> handler(Request request) async {
    if (request.method == 'POST' && request.url.path == 'upload') {
      return _handleUpload(request);
    }
    return Response.ok(_htmlPage,
        headers: {'Content-Type': 'text/html; charset=utf-8'});
  }

  /// ===============================
  /// 启动 Web 服务
  /// ===============================
  Future<void> _startServer() async {
    try {
      final ip = await _getLocalIp();
      int port = 0; // 使用0表示让系统自动分配可用端口
      HttpServer? server;
      
      // 尝试启动服务器，使用系统自动分配端口
      print('Attempting to start server on 0.0.0.0 (port auto-select)');
      server = await shelf_io.serve(
        handler, 
        InternetAddress.anyIPv4, // 使用anyIPv4确保绑定到所有IPv4接口
        port
      );
      
      port = server.port; // 获取实际分配的端口
      print('Server started successfully on 0.0.0.0:$port');
      
      // 获取服务器的实际地址信息
      final serverAddress = server.address;
      final serverPort = server.port;
      print('Server bound to: $serverAddress:$serverPort');
      
      // 打印所有网络接口信息供调试
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (var interface in interfaces) {
        print('Network interface: ${interface.name}');
        for (var addr in interface.addresses) {
          print('  Address: ${addr.address} (loopback: ${addr.isLoopback})');
        }
      }
      
      _server = server;
      _serverUrl = 'http://$ip:$port';
      _isRunning = true;
      print('Server URL for clients: $_serverUrl');
      print('To test: Try accessing http://localhost:$port from the same device');

      if (mounted) setState(() {});
    } catch (e) {
      print('Failed to start server: $e');
      // 显示详细错误信息给用户
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动服务器失败: $e\n请检查网络连接和权限')),
        );
      }
    }
  }

  /// ===============================
  /// 停止服务
  /// ===============================
  void _stopServer() {
    _server?.close(force: true);
    _server = null;
    _isRunning = false;
    _serverUrl = '';
    if (mounted) setState(() {});
  }

  /// ===============================
  /// 处理文件上传（核心）
  /// ===============================
  Future<Response> _handleUpload(Request request) async {
    try {
      final contentType = request.headers['content-type'];
      if (contentType == null || !contentType.contains('multipart/form-data')) {
        return Response.badRequest(body: 'Invalid content type');
      }

      final boundary =
          contentType.split('boundary=').last.trim();
      final bytes = await request.read().expand((e) => e).toList();
      final body = utf8.decode(bytes);

      final parts = body.split('--$boundary');
      for (final part in parts) {
        if (!part.contains('filename="')) continue;

        final nameMatch =
            RegExp(r'filename="([^"]+)"').firstMatch(part);
        if (nameMatch == null) continue;

        final filename = nameMatch.group(1)!;
        if (!filename.endsWith('.txt')) continue;

        final contentIndex = part.indexOf('\r\n\r\n');
        if (contentIndex == -1) continue;

        final content = part.substring(contentIndex + 4).trim();

        final dir = Directory(_novelDirPath!);
        final file = File('${dir.path}/$filename');
        await file.writeAsString(content);

        // 上传成功后，创建Novel对象并添加到书架
        final novel = Novel(
          id: filename,
          title: filename.replaceAll('.txt', ''),
          author: '本地导入',
          coverUrl: '',
          description: '本地导入的小说',
          chapterCount: 1, // 简单处理，将整个文件视为一章
          category: '本地',
          lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
          lastChapterTitle: '第一章',
        );

        // 获取NovelProvider实例并添加小说到书架
        if (mounted) {
          Provider.of<NovelProvider>(context, listen: false).addToFavorites(novel);
        }

        return Response.ok('OK');
      }

      return Response.badRequest(body: 'No valid file');
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }

  /// ===============================
  /// 点击入口（总流程）
  /// ===============================
  Future<void> _onPressed() async {
    final ok = await _ensureNovelDirectory();
    if (!ok || _novelDirPath == null) return;

    if (!_isRunning) {
      await _startServer();
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('📚 小说导入服务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('浏览器访问：'),
            const SizedBox(height: 6),
            SelectableText(
              _serverUrl,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              '保存目录：\n$_novelDirPath',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _stopServer();
              Navigator.pop(context);
            },
            child: const Text('停止服务'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _handleLocalFileImport();
            },
            child: const Text('导入书籍'),
          ),
        ],
      ),
    );
  }

  /// ===============================
  /// UI
  /// ===============================
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Web服务',
              style: TextStyle(fontSize: 14),
            ),
            Switch(
              value: _isRunning,
              onChanged: (value) async {
                if (value) {
                  // 开启服务
                  await _ensureNovelDirectory();
                  await _startServer();
                } else {
                  // 关闭服务
                  _stopServer();
                }
              },
            ),
          ],
        ),
        if (_isRunning && _serverUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _serverUrl,
            style: TextStyle(
              fontSize: 14,
              color: Colors.blue,
              decoration: TextDecoration.underline,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '在浏览器中打开以上地址上传小说',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ] else if (!_isRunning) ...[
          const SizedBox(height: 4),
          Text(
            '开启后可通过浏览器上传小说',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ],
    );
  }

  /// ===============================
  /// HTML 页面
  /// ===============================
  /// ===============================
  /// 处理本地文件导入
  /// ===============================
  Future<void> _handleLocalFileImport() async {
    try {
      // 打开文件选择器，允许选择多个txt文件
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        allowMultiple: true,
        dialogTitle: '选择要导入的小说文件',
        withData: false, // 不读取文件内容，提高性能
        withReadStream: false, // 不使用流
      );

      if (result == null || result.files.isEmpty) {
        return; // 用户取消选择
      }

      // 确保小说目录存在
      await _ensureNovelDirectory();
      if (_novelDirPath == null) {
        throw Exception('无法获取小说目录');
      }

      // 获取当前已存在的小说ID列表（用于去重）
      final novelProvider = Provider.of<NovelProvider>(context, listen: false);
      final existingNovelIds = novelProvider.favoriteNovels.map((n) => n.id).toSet();

      // 获取已存在的本地文件列表（用于去重）
      final dir = Directory(_novelDirPath!);
      final existingFiles = dir.listSync()
          .where((entity) => entity is File && entity.path.endsWith('.txt'))
          .cast<File>()
          .map((file) => path.basename(file.path))
          .toSet();

      // 导入选中的文件
      int successCount = 0;
      int skipCount = 0;

      for (final pickedFile in result.files) {
        final fileName = path.basename(pickedFile.path!);
        
        // 检查是否已存在（本地文件或书架中）
        if (existingFiles.contains(fileName) || existingNovelIds.contains(fileName)) {
          skipCount++;
          continue;
        }

        // 读取文件内容，支持多种编码
        final sourceFile = File(pickedFile.path!);
        final bytes = await sourceFile.readAsBytes();
        String content;
        
        try {
          // 先尝试UTF-8编码
          content = utf8.decode(bytes);
        } catch (e) {
          try {
            // 尝试GBK编码（中文常用编码）
            content = await CharsetConverter.decode("GBK", bytes);
          } catch (e) {
            try {
              // 尝试GB2312编码
              content = await CharsetConverter.decode("GB2312", bytes);
            } catch (e) {
              // 最后尝试Latin1编码
              content = latin1.decode(bytes);
            }
          }
        }

        // 保存到小说目录
        final targetFile = File('${_novelDirPath!}/$fileName');
        await targetFile.writeAsString(content);

        // 创建Novel对象并添加到书架
        final novel = Novel(
          id: fileName,
          title: fileName.replaceAll('.txt', ''),
          author: '本地导入',
          coverUrl: '',
          description: '本地导入的小说',
          chapterCount: 1,
          category: '本地',
          lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
          lastChapterTitle: '第一章',
        );

        novelProvider.addToFavorites(novel);
        successCount++;
      }

      // 显示导入结果
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '导入完成：成功 $successCount 本，跳过已存在 $skipCount 本',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('导入文件失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static final String _htmlPage = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>小说上传</title>
<style>
body{font-family:Arial;padding:40px;max-width:600px;margin:0 auto;}
h2{color:#333;}
.drop-zone{border:3px dashed #ccc;padding:40px;text-align:center;border-radius:10px;margin:20px 0;cursor:pointer;transition:all 0.3s;}
.drop-zone:hover{border-color:#2196F3;background:#f5f5ff;}
.drop-zone.dragover{border-color:#4CAF50;background:#e8f5e9;}
.btn{background:#2196F3;color:white;border:none;padding:12px 24px;border-radius:6px;cursor:pointer;font-size:16px;margin:10px 5px;}
.btn:hover{background:#1976D2}
.btn:disabled{background:#ccc}
#msg{padding:15px;border-radius:6px;margin-top:20px;display:none;}
.success{background:#d4edda;color:#155724;border:1px solid #c3e6cb;}
.error{background:#f8d7da;color:#721c24;border:1px solid #f5c6cb}
.info{background:#fff3cd;color:#856404;border:1px solid #ffeeba}
.file-info{background:#e7f3ff;padding:15px;border-radius:6px;margin:15px 0;font-size:14px;}
</style>
</head>
<body>
<h2>📚 上传 TXT 小说</h2>

<div class="drop-zone" id="dropZone">
  <p style="font-size:18px;">📁 点击选择文件 或 拖拽文件到此处</p>
  <p style="color:#999;">支持 .txt 格式</p>
</div>

<input type="file" id="fileInput" accept=".txt" style="display:none"/>

<button class="btn" id="uploadBtn" onclick="upload()">📤 上传文件</button>
<button class="btn" onclick="location.reload()" style="background:#6c757d">🔄 刷新页面</button>

<div id="fileInfo" class="file-info" style="display:none"></div>
<div id="msg"></div>

<script>
const dropZone=document.getElementById('dropZone');
const fileInput=document.getElementById('fileInput');
let selectedFile=null;

dropZone.onclick=()=>fileInput.click();
dropZone.ondragover=(e)=>{e.preventDefault();dropZone.classList.add('dragover');};
dropZone.ondragleave=()=>dropZone.classList.remove('dragover');
dropZone.ondrop=(e)=>{
  e.preventDefault();
  dropZone.classList.remove('dragover');
  if(e.dataTransfer.files.length){
    handleFile(e.dataTransfer.files[0]);
  }
};
fileInput.onchange=()=>{
  if(fileInput.files.length)handleFile(fileInput.files[0]);
};

function handleFile(file){
  if(!file.name.endsWith('.txt')){
    showMsg('❌ 请选择 .txt 文件','error');
    return;
  }
  selectedFile=file;
  document.getElementById('fileInfo').innerHTML=`
    <strong>📄 已选择：</strong>\${file.name}<br>
    <strong>📊 大小：</strong>\${(file.size/1024).toFixed(1)} KB
  `;
  document.getElementById('fileInfo').style.display='block';
  showMsg('文件已选择，点击"上传文件"按钮','info');
}

function showMsg(text,type){
  const msg=document.getElementById('msg');
  msg.innerHTML=text;
  msg.className=type;
  msg.style.display='block';
}

async function upload(){
  if(!selectedFile){
    showMsg('❌ 请先选择文件','error');
    return;
  }
  
  document.getElementById('uploadBtn').disabled=true;
  document.getElementById('uploadBtn').innerText='⏳ 上传中...';
  showMsg('⏳ 正在上传...','info');
  
  try{
    const fd=new FormData();
    fd.append('file',selectedFile);
    const res=await fetch('/upload',{method:'POST',body:fd});
    const text=await res.text();
    
    if(res.ok){
      showMsg(`✅ 上传成功！<br>📄 文件：\${selectedFile.name}<br>💾 已保存到小说目录<br><br><strong>提示：返回App点击"刷新"按钮查看导入的小说</strong>`,'success');
    }else{
      showMsg(`❌ 上传失败：\${text}`,'error');
    }
  }catch(e){
    showMsg(`❌ 错误：\${e.message}`,'error');
  }finally{
    document.getElementById('uploadBtn').disabled=false;
    document.getElementById('uploadBtn').innerText='📤 上传文件';
    selectedFile=null;
  }
}
</script>
</body>
</html>
''';
}
