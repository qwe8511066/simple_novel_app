import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

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
      // 获取所有网络接口
      final interfaces = await NetworkInterface.list();
      
      // 遍历所有接口，优先选择WiFi接口
      for (var interface in interfaces) {
        // 查找WiFi接口（通常名称包含'wlan'或'Wi-Fi'）
        final isWiFi = interface.name.toLowerCase().contains('wlan') || 
                      interface.name.toLowerCase().contains('wi-fi');
        
        for (var addr in interface.addresses) {
          // 确保是IPv4地址且不是回环地址
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            // 如果是WiFi接口，直接返回
            if (isWiFi) {
              return addr.address;
            }
          }
        }
      }
      
      // 如果没有找到WiFi接口，返回第一个非回环IPv4地址
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      // 如果出现错误，返回127.0.0.1
    }
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
      const port = 8080;
      
      // 尝试在不同的地址上启动服务器，确保可以接受外部连接
      print('Attempting to start server on 0.0.0.0:$port');
      _server = await shelf_io.serve(handler, '0.0.0.0', port);
      print('Server started successfully on 0.0.0.0:$port');
      
      // 获取服务器的实际地址信息
      final serverAddress = _server?.address;
      final serverPort = _server?.port;
      print('Server bound to: $serverAddress:$serverPort');
      
      _serverUrl = 'http://$ip:$port';
      _isRunning = true;
      print('Server URL for clients: $_serverUrl');

      if (mounted) setState(() {});
    } catch (e) {
      print('Failed to start server: $e');
      // 显示错误信息给用户
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动服务器失败: $e')),
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
        ],
      ),
    );
  }

  /// ===============================
  /// UI
  /// ===============================
  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _onPressed,
      icon: Icon(_isRunning ? Icons.wifi : Icons.upload_file),
      label: Text(_isRunning ? '服务运行中' : '导入小说'),
      style: ElevatedButton.styleFrom(
        backgroundColor: _isRunning ? Colors.green : Colors.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    );
  }

  /// ===============================
  /// HTML 页面
  /// ===============================
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
