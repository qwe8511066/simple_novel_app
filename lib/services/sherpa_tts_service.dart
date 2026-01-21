import 'dart:io';
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

      final tokensPath = '${File(modelPath).parent.path}/tokens.txt';
      final lexiconPath = '${File(modelPath).parent.path}/lexicon.txt';

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

      // 创建TTS配置
      final config = OfflineTtsConfig(
        model: OfflineTtsModelConfig(
          vits: OfflineTtsVitsModelConfig(
            model: modelPath,
            lexicon: lexiconPath,
            tokens: tokensPath,
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

      // 同样处理tokens文件
      final tokensDestPath = '${modelsDir.path}/tokens.txt';
      final tokensFile = File(tokensDestPath);

      final lexiconDestPath = '${modelsDir.path}/lexicon.txt';
      final lexiconFile = File(lexiconDestPath);

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