import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart';

class TtsIsolateWorker {
  static void entryPoint(SendPort initialReplyTo) {
    final port = ReceivePort();
    initialReplyTo.send(port.sendPort);

    initBindings();

    OfflineTts? tts;

    Future<void> handle(Map<dynamic, dynamic> msg) async {
      final type = msg['type'] as String?;
      final int id = (msg['id'] as int?) ?? 0;
      final SendPort replyTo = msg['replyTo'] as SendPort;

      try {
        switch (type) {
          case 'init':
            final model = msg['model'] as String;
            final tokens = msg['tokens'] as String;
            final lexicon = msg['lexicon'] as String;
            final vocoder = msg['vocoder'] as String;
            final dataDir = msg['dataDir'] as String;

            final config = OfflineTtsConfig(
              model: OfflineTtsModelConfig(
                matcha: OfflineTtsMatchaModelConfig(
                  acousticModel: model,
                  vocoder: vocoder,
                  tokens: tokens,
                  dataDir: dataDir,
                  lexicon: lexicon,
                ),
              ),
            );

            tts = OfflineTts(config);
            replyTo.send({'id': id, 'ok': true, 'numSpeakers': tts!.numSpeakers});
            return;

          case 'synthesizeToWav':
            final current = tts;
            if (current == null) {
              replyTo.send({'id': id, 'ok': false, 'error': 'TTS not initialized'});
              return;
            }

            final text = msg['text'] as String;
            final sid = (msg['sid'] as int?) ?? 0;
            final speed = (msg['speed'] as double?) ?? 1.0;
            final outPath = msg['outPath'] as String;

            final audio = current.generate(text: text, sid: sid, speed: speed);
            final samples = _float32ToInt16(audio.samples);
            final bytes = _wavBytesFromInt16Samples(samples, audio.sampleRate, 16, 1);

            final outFile = File(outPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(bytes, flush: true);

            replyTo.send({
              'id': id,
              'ok': true,
              'path': outPath,
              'sampleRate': audio.sampleRate,
            });
            return;

          case 'dispose':
            tts = null;
            replyTo.send({'id': id, 'ok': true});
            return;

          default:
            replyTo.send({'id': id, 'ok': false, 'error': 'Unknown message type: $type'});
            return;
        }
      } catch (e) {
        replyTo.send({'id': id, 'ok': false, 'error': e.toString()});
      }
    }

    port.listen((dynamic message) {
      if (message is Map) {
        handle(message.cast<dynamic, dynamic>());
      }
    });
  }

  static Uint8List _wavBytesFromInt16Samples(
    Int16List pcmData,
    int sampleRate,
    int bitDepth,
    int channels,
  ) {
    final byteRate = sampleRate * channels * bitDepth ~/ 8;
    final blockAlign = channels * bitDepth ~/ 8;
    final dataSize = pcmData.lengthInBytes;
    final fileSize = 44 + dataSize;

    final wavData = Uint8List(fileSize);
    final byteData = wavData.buffer.asByteData();

    byteData.setUint8(0, 0x52);
    byteData.setUint8(1, 0x49);
    byteData.setUint8(2, 0x46);
    byteData.setUint8(3, 0x46);

    byteData.setUint32(4, fileSize - 8, Endian.little);

    byteData.setUint8(8, 0x57);
    byteData.setUint8(9, 0x41);
    byteData.setUint8(10, 0x56);
    byteData.setUint8(11, 0x45);

    byteData.setUint8(12, 0x66);
    byteData.setUint8(13, 0x6d);
    byteData.setUint8(14, 0x74);
    byteData.setUint8(15, 0x20);

    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, channels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, byteRate, Endian.little);
    byteData.setUint16(32, blockAlign, Endian.little);
    byteData.setUint16(34, bitDepth, Endian.little);

    byteData.setUint8(36, 0x64);
    byteData.setUint8(37, 0x61);
    byteData.setUint8(38, 0x74);
    byteData.setUint8(39, 0x61);

    byteData.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < pcmData.length; i++) {
      byteData.setInt16(44 + i * 2, pcmData[i], Endian.little);
    }

    return wavData;
  }

  static Int16List _float32ToInt16(Float32List pcmData) {
    final out = Int16List(pcmData.length);
    for (var i = 0; i < pcmData.length; i++) {
      var v = pcmData[i];
      if (v > 1.0) v = 1.0;
      if (v < -1.0) v = -1.0;
      out[i] = (v * 32767).round();
    }
    return out;
  }
}
