import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

import 'tts_isolate_worker.dart';

class SherpaTtsService {
  static bool _bindingsInitialized = false;

  Future<bool>? _initializeFuture;

  OfflineTts? _tts;
  bool _isInitialized = false;
  int _lastSampleRate = 24000;

  SendPort? _workerSendPort;
  ReceivePort? _workerReceivePort;
  Isolate? _workerIsolate;
  int _workerMsgId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _workerPending =
      <int, Completer<Map<String, dynamic>>>{};

  String? _modelPath;
  String? _tokensPath;
  String? _lexiconPath;
  String? _vocoderPath;
  String? _espeakDataDirPath;

  int get numSpeakers => _tts?.numSpeakers ?? 0;
  int get lastSampleRate => _lastSampleRate;

  bool get isolateReady => _workerSendPort != null;

  Future<List<String>> _listAllAssetKeys() async {
    // AssetManifest.json tends to be the most universally available format.
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestJson) as Map<String, dynamic>;
      return manifestMap.keys.toList(growable: false);
    } catch (_) {
      // Fall back to the newer AssetManifest API if json is unavailable.
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest.listAssets().toList(growable: false);
    }
  }

  Future<void> _copyAssetDirToDisk({
    required String assetDirPrefix,
    required String destDirPath,
    bool forceCopy = false,
  }) async {
    final destDir = Directory(destDirPath);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    final assets = await _listAllAssetKeys();
    var matched = 0;

    for (final entry in assets) {
      if (!entry.startsWith(assetDirPrefix)) {
        continue;
      }

      matched++;

      final relativePath = entry.substring(assetDirPrefix.length);
      final outFile = File('$destDirPath/$relativePath');

      if (!forceCopy && await outFile.exists()) continue;

      await outFile.parent.create(recursive: true);
      final data = await rootBundle.load(entry);
      await outFile.writeAsBytes(data.buffer.asUint8List());
    }

    print('已匹配并处理assets目录: $assetDirPrefix, 文件数: $matched');
  }

  /// 初始化TTS服务
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    final inflight = _initializeFuture;
    if (inflight != null) return inflight;

    final f = Future<bool>(() async {
      try {
        print('开始初始化Sherpa TTS服务...');

        if (!_bindingsInitialized) {
          initBindings();
          _bindingsInitialized = true;
        }

        // 获取应用文档目录
        final documentsDir = await getApplicationDocumentsDirectory();
        final modelsDir = Directory('${documentsDir.path}/models');

        // 确保模型目录存在
        if (!await modelsDir.exists()) {
          await modelsDir.create(recursive: true);
        }

        // 复制模型文件到应用目录
        final modelPath = await _extractModelToAppDir();
        if (modelPath == null) {
          print('模型文件提取失败');
          return false;
        }

        print('模型文件路径: $modelPath');

        final modelDirPath = File(modelPath).parent.path;
        final tokensPath = '$modelDirPath/tokens.txt';
        final lexiconPath = '$modelDirPath/lexicon.txt';
        final vocoderPath = '$modelDirPath/vocos.onnx';
        final espeakDataDirPath = '$modelDirPath/espeak-ng-data';

        _modelPath = modelPath;
        _tokensPath = tokensPath;
        _lexiconPath = lexiconPath;
        _vocoderPath = vocoderPath;
        _espeakDataDirPath = espeakDataDirPath;

        if (!await File(modelPath).exists()) {
          print('模型文件不存在: $modelPath');
          return false;
        }

        if (!await File(tokensPath).exists()) {
          print('Tokens文件不存在: $tokensPath');
          return false;
        }

        if (!await File(lexiconPath).exists()) {
          print('Lexicon文件不存在: $lexiconPath');
          return false;
        }

        if (!await File(vocoderPath).exists()) {
          print('Vocoder文件不存在: $vocoderPath');
          return false;
        }

        if (!await Directory(espeakDataDirPath).exists()) {
          print('espeak-ng-data目录不存在: $espeakDataDirPath');
          return false;
        }

        // 创建TTS配置
        final config = OfflineTtsConfig(
          model: OfflineTtsModelConfig(
            matcha: OfflineTtsMatchaModelConfig(
              acousticModel: modelPath,
              vocoder: vocoderPath,
              tokens: tokensPath,
              dataDir: espeakDataDirPath,
              lexicon: lexiconPath,
            ),
          ),
        );

        // 创建TTS实例
        _tts = OfflineTts(config);

        _isInitialized = true;
        print('TTS服务初始化成功');

        await _ensureWorkerInitialized();
        return true;
      } catch (e) {
        print('TTS初始化失败: $e');
        _isInitialized = false;
        return false;
      }
    });

    _initializeFuture = f;
    try {
      return await f;
    } finally {
      if (identical(_initializeFuture, f)) {
        _initializeFuture = null;
      }
    }
  }

  Future<void> _ensureWorkerInitialized() async {
    if (_workerSendPort != null) return;
    final modelPath = _modelPath;
    final tokensPath = _tokensPath;
    final lexiconPath = _lexiconPath;
    final vocoderPath = _vocoderPath;
    final espeakDataDirPath = _espeakDataDirPath;
    if (modelPath == null ||
        tokensPath == null ||
        lexiconPath == null ||
        vocoderPath == null ||
        espeakDataDirPath == null) {
      return;
    }

    final ready = Completer<void>();
    final receive = ReceivePort();
    _workerReceivePort = receive;

    receive.listen((dynamic message) {
      if (message is SendPort) {
        _workerSendPort = message;
        if (!ready.isCompleted) {
          ready.complete();
        }
        return;
      }
      if (message is Map) {
        final m = message.cast<String, dynamic>();
        final id = m['id'];
        if (id is int) {
          final c = _workerPending.remove(id);
          c?.complete(m);
        }
      }
    });

    _workerIsolate = await Isolate.spawn(
      TtsIsolateWorker.entryPoint,
      receive.sendPort,
    );

    await ready.future;
    final sendPort = _workerSendPort;
    if (sendPort == null) return;

    final resp = await _workerRequest(<String, dynamic>{
      'type': 'init',
      'model': modelPath,
      'tokens': tokensPath,
      'lexicon': lexiconPath,
      'vocoder': vocoderPath,
      'dataDir': espeakDataDirPath,
    });

    if (resp['ok'] != true) {
      _workerSendPort = null;
    }
  }

  Future<Map<String, dynamic>> _workerRequest(Map<String, dynamic> msg) async {
    final sendPort = _workerSendPort;
    final receive = _workerReceivePort;
    if (sendPort == null || receive == null) {
      return <String, dynamic>{'ok': false, 'error': 'Worker not ready'};
    }

    final id = ++_workerMsgId;
    final c = Completer<Map<String, dynamic>>();
    _workerPending[id] = c;

    sendPort.send(<String, dynamic>{
      ...msg,
      'id': id,
      'replyTo': receive.sendPort,
    });

    return c.future;
  }

  Future<String?> synthesizeToWavFile(
    String text, {
    int sid = 0,
    double speed = 1.0,
  }) async {
    if (!_isInitialized) {
      print('TTS服务未初始化');
      return null;
    }

    await _ensureWorkerInitialized();
    if (_workerSendPort == null) {
      return null;
    }

    final normalizedText = _normalizeNumbersForZh(text);
    final tmp = await getTemporaryDirectory();
    final safeId = normalizedText.hashCode;
    final outPath = '${tmp.path}/tts_${sid}_${speed}_${safeId}.wav';

    final resp = await _workerRequest(<String, dynamic>{
      'type': 'synthesizeToWav',
      'text': normalizedText,
      'sid': sid,
      'speed': speed,
      'outPath': outPath,
    });

    if (resp['ok'] == true) {
      final sr = resp['sampleRate'];
      if (sr is int) {
        _lastSampleRate = sr;
      }
      return resp['path'] as String?;
    }
    return null;
  }

  /// 合成文本为音频
  Future<List<double>?> synthesizeText(
    String text, {
    int sid = 0,
    double speed = 1.0,
  }) async {
    if (!_isInitialized || _tts == null) {
      print('TTS服务未初始化');
      return null;
    }

    try {
      final normalizedText = _normalizeNumbersForZh(text);
      print('开始合成文本: $normalizedText');

      final audio = _tts!.generate(
        text: normalizedText,
        sid: sid,
        speed: speed,
      );

      _lastSampleRate = audio.sampleRate;

      print('音频生成成功，样本数: ${audio.samples.length}, 采样率: ${audio.sampleRate}');

      // 将Int16格式的音频数据转换为Double格式
      final List<double> audioData = audio.samples.map((sample) => sample.toDouble()).toList();

      return audioData;
    } catch (e) {
      print('语音合成失败: $e');
      return null;
    }
  }

  String _normalizeNumbersForZh(String input) {
    if (input.isEmpty) return input;

    String _toAsciiDigits(String s) {
      final b = StringBuffer();
      for (final r in s.runes) {
        if (r >= 0xFF10 && r <= 0xFF19) {
          b.writeCharCode(0x30 + (r - 0xFF10));
        } else {
          b.writeCharCode(r);
        }
      }
      return b.toString();
    }

    final s = _toAsciiDigits(input);

    return s.replaceAllMapped(RegExp(r'\d+(?:\.\d+)?'), (m) {
      final token = m.group(0) ?? '';
      if (token.isEmpty) return token;
      if (token.contains('.')) {
        final parts = token.split('.');
        final intPart = parts.isNotEmpty ? parts[0] : '';
        final fracPart = parts.length > 1 ? parts[1] : '';
        final head = _intToZh(intPart);
        final tail = fracPart.split('').map(_digitToZh).join();
        if (tail.isEmpty) return head;
        return '$head点$tail';
      }
      return _intToZh(token);
    });
  }

  String _digitToZh(String d) {
    switch (d) {
      case '0':
        return '零';
      case '1':
        return '一';
      case '2':
        return '二';
      case '3':
        return '三';
      case '4':
        return '四';
      case '5':
        return '五';
      case '6':
        return '六';
      case '7':
        return '七';
      case '8':
        return '八';
      case '9':
        return '九';
      default:
        return d;
    }
  }

  String _intToZh(String digits) {
    if (digits.isEmpty) return digits;

    final clean = digits.replaceFirst(RegExp(r'^0+'), '');
    if (clean.isEmpty) return '零';

    if (clean.length > 4) {
      return clean.split('').map(_digitToZh).join();
    }

    final n = int.tryParse(clean);
    if (n == null) {
      return clean.split('').map(_digitToZh).join();
    }

    if (n < 10) return _digitToZh(clean);

    final units = ['', '十', '百', '千'];
    final ds = clean.split('').map((e) => int.parse(e)).toList(growable: false);
    final len = ds.length;
    final b = StringBuffer();
    var zeroPending = false;
    for (var i = 0; i < len; i++) {
      final digit = ds[i];
      final pos = len - 1 - i;
      if (digit == 0) {
        zeroPending = true;
        continue;
      }
      if (zeroPending && b.isNotEmpty) {
        b.write('零');
      }
      zeroPending = false;

      if (!(digit == 1 && pos == 1 && b.isEmpty)) {
        b.write(_digitToZh(digit.toString()));
      }
      b.write(units[pos]);
    }
    return b.toString();
  }

  /// 提取模型文件到应用目录
  Future<String?> _extractModelToAppDir() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${documentsDir.path}/models');

      // 确保模型目录存在
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      // 检查模型文件是否已经存在
      final modelDestPath = '${modelsDir.path}/model.onnx';
      final modelFile = File(modelDestPath);

      final vocoderDestPath = '${modelsDir.path}/vocos.onnx';
      final vocoderFile = File(vocoderDestPath);

      // 同样处理tokens文件
      final tokensDestPath = '${modelsDir.path}/tokens.txt';
      final tokensFile = File(tokensDestPath);

      final lexiconDestPath = '${modelsDir.path}/lexicon.txt';
      final lexiconFile = File(lexiconDestPath);

      final espeakDataDir = Directory('${modelsDir.path}/espeak-ng-data');

      if (!await modelFile.exists()) {
        // 从assets复制模型文件
        final modelAssetPath = 'assets/models/model.onnx';
        final ByteData modelData = await rootBundle.load(modelAssetPath);
        final List<int> modelBytes = modelData.buffer.asUint8List();
        await modelFile.writeAsBytes(modelBytes);
        print('模型文件已复制到: $modelDestPath');
      } else {
        print('模型文件已存在于: $modelDestPath');
      }

      if (!await vocoderFile.exists()) {
        final vocoderAssetPath = 'assets/models/vocos.onnx';
        final vocoderData = await rootBundle.load(vocoderAssetPath);
        await vocoderFile.writeAsBytes(vocoderData.buffer.asUint8List());
        print('Vocoder文件已复制到: $vocoderDestPath');
      } else {
        print('Vocoder文件已存在于: $vocoderDestPath');
      }

      if (!await tokensFile.exists()) {
        final tokensAssetPath = 'assets/models/tokens.txt';
        final tokensData = await rootBundle.load(tokensAssetPath);
        final tokensBytes = tokensData.buffer.asUint8List();
        await tokensFile.writeAsBytes(tokensBytes);
        print('Tokens文件已复制到: $tokensDestPath');
      } else {
        print('Tokens文件已存在于: $tokensDestPath');
      }

      if (!await lexiconFile.exists()) {
        final lexiconAssetPath = 'assets/models/lexicon.txt';
        final lexiconData = await rootBundle.load(lexiconAssetPath);
        final lexiconBytes = lexiconData.buffer.asUint8List();
        await lexiconFile.writeAsBytes(lexiconBytes);
        print('Lexicon文件已复制到: $lexiconDestPath');
      } else {
        print('Lexicon文件已存在于: $lexiconDestPath');
      }

      if (!await espeakDataDir.exists()) {
        await _copyAssetDirToDisk(
          assetDirPrefix: 'assets/models/espeak-ng-data/',
          destDirPath: espeakDataDir.path,
          forceCopy: false,
        );
      }

      return modelDestPath;
    } catch (e) {
      print('提取模型文件失败: $e');
      return null;
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    _initializeFuture = null;
    _tts = null;
    _isInitialized = false;

    try {
      final sendPort = _workerSendPort;
      if (sendPort != null && _workerReceivePort != null) {
        unawaited(_workerRequest(<String, dynamic>{'type': 'dispose'}));
      }
    } catch (_) {}

    for (final c in _workerPending.values) {
      if (!c.isCompleted) {
        c.complete(<String, dynamic>{'ok': false, 'error': 'disposed'});
      }
    }
    _workerPending.clear();

    _workerReceivePort?.close();
    _workerReceivePort = null;

    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _workerSendPort = null;
  }

  void unawaited(Future<void> f) {
    f.catchError((_) {});
  }
}