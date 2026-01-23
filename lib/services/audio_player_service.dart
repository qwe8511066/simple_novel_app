import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

class AudioPlayerService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  StreamSubscription<void>? _completeSub;

  /// 播放PCM音频数据
  /// [pcmData] - PCM格式的音频数据
  /// [sampleRate] - 采样率，默认24000Hz
  /// [bitDepth] - 位深度，默认16位
  /// [channels] - 声道数，默认1（单声道）
  Future<void> playPcmAudio(List<double> pcmData, {
    int sampleRate = 24000,
    int bitDepth = 16,
    int channels = 1,
  }) async {
    try {
      // 停止当前播放
      await stop();

      // 将double格式的PCM数据转换为16位整数
      final Int16List int16Data = convertToInt16(pcmData);
      
      // 创建WAV文件头
      final Uint8List wavData = createWavFile(int16Data, sampleRate, bitDepth, channels);
      
      // 将WAV数据保存到临时文件
      final File tempFile = await saveToTempFile(wavData);
      
      // 播放临时文件
      await _audioPlayer.play(UrlSource(tempFile.path));
      _isPlaying = true;

      // 监听播放完成事件（仅用于更新状态+清理文件）
      await _completeSub?.cancel();
      _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
        _isPlaying = false;
        try {
          if (tempFile.existsSync()) {
            tempFile.deleteSync();
          }
        } catch (_) {}
      });
    } catch (e) {
      print('播放音频失败: $e');
      _isPlaying = false;
    }
  }

  /// 播放PCM音频并等待播放完成（用于串行朗读/高亮）
  Future<void> playPcmAudioAndWait(
    List<double> pcmData, {
    int sampleRate = 24000,
    int bitDepth = 16,
    int channels = 1,
  }) async {
    // 停止当前播放
    await stop();

    // 将double格式的PCM数据转换为16位整数
    final Int16List int16Data = convertToInt16(pcmData);

    // 创建WAV文件头
    final Uint8List wavData = createWavFile(int16Data, sampleRate, bitDepth, channels);

    // 将WAV数据保存到临时文件
    final File tempFile = await saveToTempFile(wavData);

    final completer = Completer<void>();

    await _completeSub?.cancel();
    _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
      _isPlaying = false;
      try {
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
      } catch (_) {}
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await _audioPlayer.play(UrlSource(tempFile.path));
      _isPlaying = true;
      await completer.future;
    } catch (e) {
      _isPlaying = false;
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
      rethrow;
    }
  }

  /// 播放WAV文件并等待播放完成
  Future<void> playWavFileAndWait(String filePath) async {
    await stop();

    final completer = Completer<void>();

    await _completeSub?.cancel();
    _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
      _isPlaying = false;
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await _audioPlayer.play(DeviceFileSource(filePath));
      _isPlaying = true;
      await completer.future;
    } catch (e) {
      _isPlaying = false;
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
      rethrow;
    }
  }

  /// 停止当前播放
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _isPlaying = false;
    } catch (e) {
      print('停止播放失败: $e');
    }
  }

  /// 暂停当前播放
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
      _isPlaying = false;
    } catch (e) {
      print('暂停播放失败: $e');
    }
  }

  /// 恢复播放
  Future<void> resume() async {
    try {
      await _audioPlayer.resume();
      _isPlaying = true;
    } catch (e) {
      _isPlaying = false;
      print('恢复播放失败: $e');
    }
  }

  /// 获取当前播放状态
  bool get isPlaying => _isPlaying;

  /// 释放资源
  Future<void> dispose() async {
    try {
      await _completeSub?.cancel();
      _completeSub = null;
      await _audioPlayer.dispose();
    } catch (e) {
      print('释放音频资源失败: $e');
    }
  }

  /// 将double格式的PCM数据转换为16位整数
  Int16List convertToInt16(List<double> pcmData) {
    final Int16List int16Data = Int16List(pcmData.length);
    for (int i = 0; i < pcmData.length; i++) {
      // 将double值（范围-1.0到1.0）转换为16位整数（范围-32768到32767）
      double value = pcmData[i];
      if (value > 1.0) value = 1.0;
      if (value < -1.0) value = -1.0;
      int16Data[i] = (value * 32767).round();
    }
    return int16Data;
  }

  /// 创建WAV文件数据
  Uint8List createWavFile(Int16List pcmData, int sampleRate, int bitDepth, int channels) {
    final int byteRate = sampleRate * channels * bitDepth ~/ 8;
    final int blockAlign = channels * bitDepth ~/ 8;
    final int dataSize = pcmData.lengthInBytes;
    final int fileSize = 44 + dataSize;

    final Uint8List wavData = Uint8List(fileSize);
    final ByteData byteData = wavData.buffer.asByteData();

    // RIFF标识符
    byteData.setUint8(0, 0x52); // R
    byteData.setUint8(1, 0x49); // I
    byteData.setUint8(2, 0x46); // F
    byteData.setUint8(3, 0x46); // F

    // 文件大小
    byteData.setUint32(4, fileSize - 8, Endian.little);

    // WAVE标识符
    byteData.setUint8(8, 0x57); // W
    byteData.setUint8(9, 0x41); // A
    byteData.setUint8(10, 0x56); // V
    byteData.setUint8(11, 0x45); // E

    // fmt子块标识符
    byteData.setUint8(12, 0x66); // f
    byteData.setUint8(13, 0x6d); // m
    byteData.setUint8(14, 0x74); // t
    byteData.setUint8(15, 0x20); // space

    // fmt子块大小
    byteData.setUint32(16, 16, Endian.little);

    // 音频格式（1 = PCM）
    byteData.setUint16(20, 1, Endian.little);

    // 声道数
    byteData.setUint16(22, channels, Endian.little);

    // 采样率
    byteData.setUint32(24, sampleRate, Endian.little);

    // 字节率
    byteData.setUint32(28, byteRate, Endian.little);

    // 块对齐
    byteData.setUint16(32, blockAlign, Endian.little);

    // 位深度
    byteData.setUint16(34, bitDepth, Endian.little);

    // data子块标识符
    byteData.setUint8(36, 0x64); // d
    byteData.setUint8(37, 0x61); // a
    byteData.setUint8(38, 0x74); // t
    byteData.setUint8(39, 0x61); // a

    // data子块大小
    byteData.setUint32(40, dataSize, Endian.little);

    // 写入PCM数据
    for (int i = 0; i < pcmData.length; i++) {
      byteData.setInt16(44 + i * 2, pcmData[i], Endian.little);
    }

    return wavData;
  }

  /// 将音频数据保存到临时文件
  Future<File> saveToTempFile(Uint8List data) async {
    final Directory tempDir = await getTemporaryDirectory();
    final File tempFile = File('${tempDir.path}/temp_audio.wav');
    await tempFile.writeAsBytes(data);
    return tempFile;
  }
}