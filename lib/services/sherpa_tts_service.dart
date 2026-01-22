import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

class SherpaTtsService {
  static bool _bindingsInitialized = false;

  OfflineTts? _tts;
  bool _isInitialized = false;
  int _lastSampleRate = 24000;

  int get numSpeakers => _tts?.numSpeakers ?? 0;
  int get lastSampleRate => _lastSampleRate;

  Future<List<String>> _listAllAssetKeys() async {
    // AssetManifest.json tends to be the most universally available format.
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestJson) as Map<String, dynamic>;
      return manifestMap.keys.toList(growable: false);
    } catch (_) {
      // Fall back to the newer AssetManifest API if json is unavailable.
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return (await manifest.listAssets()).toList(growable: false);
    }
  }

  Future<void> _copyAssetDirToDisk({
    required String assetDirPrefix,
    required String destDirPath,
    bool forceCopy = true,
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
      return true;
    } catch (e) {
      print('TTS初始化失败: $e');
      _isInitialized = false;
      return false;
    }
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
      print('开始合成文本: $text');

      // 使用TTS生成音频
      final audio = _tts!.generate(
        text: text,
        sid: sid, // 说话人ID
        speed: speed, // 语速
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

  /// 释放资源
  Future<void> dispose() async {
    _tts = null;
    _isInitialized = false;
  }
}