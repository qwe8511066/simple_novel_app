import 'package:flutter/material.dart';

import '../services/audio_player_service.dart';
import '../services/sherpa_tts_service.dart';

class TtsTestPage extends StatefulWidget {
  const TtsTestPage({super.key});

  @override
  State<TtsTestPage> createState() => _TtsTestPageState();
}

class _TtsTestPageState extends State<TtsTestPage> {
  final SherpaTtsService _ttsService = SherpaTtsService();
  final AudioPlayerService _audioPlayerService = AudioPlayerService();

  final TextEditingController _textController = TextEditingController(
    text: '第三千零八十七章野生的？不，这是我散养的',
  );

  bool _ttsInitialized = false;
  String _status = '未初始化';

  int _sid = 0;
  double _speed = 1.0;

  int get _maxSid {
    final n = _ttsService.numSpeakers;
    if (n <= 0) return 0;
    return n - 1;
  }

  Future<void> _initTts() async {
    try {
      setState(() {
        _status = '正在初始化TTS...';
      });

      final ok = await _ttsService.initialize();
      if (!mounted) return;

      if (!ok) {
        setState(() {
          _ttsInitialized = false;
          _status = 'TTS初始化失败：initialize() 返回 false';
        });
        return;
      }

      final n = _ttsService.numSpeakers;
      setState(() {
        _ttsInitialized = true;
        _status = n > 0 ? 'TTS初始化成功！音色数: $n' : 'TTS初始化成功！';
        if (_sid > _maxSid) {
          _sid = 0;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ttsInitialized = false;
        _status = 'TTS初始化失败: $e';
      });
    }
  }

  Future<void> _generateAndPlay() async {
    if (!_ttsInitialized) {
      setState(() {
        _status = '请先初始化TTS';
      });
      return;
    }

    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _status = '请输入要合成的文本';
      });
      return;
    }

    try {
      setState(() {
        _status = '正在合成语音...';
      });

      final audioData = await _ttsService.synthesizeText(
        text,
        sid: _sid,
        speed: _speed,
      );

      if (!mounted) return;

      if (audioData == null || audioData.isEmpty) {
        setState(() {
          _status = '语音合成失败：没有生成音频数据';
        });
        return;
      }

      setState(() {
        _status = '正在播放语音...';
      });

      await _audioPlayerService.playPcmAudio(
        audioData,
        sampleRate: _ttsService.lastSampleRate,
      );

      if (!mounted) return;
      setState(() {
        _status = '播放中';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'TTS测试失败: $e';
      });
    }
  }

  Future<void> _stop() async {
    await _audioPlayerService.stop();
    if (!mounted) return;
    setState(() {
      _status = '已停止';
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _ttsService.dispose();
    _audioPlayerService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final numSpeakers = _ttsService.numSpeakers;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _status,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _initTts,
            child: const Text('初始化TTS'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '要合成的文本',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _sid,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '音色 (sid)',
                  ),
                  items: List.generate(
                    numSpeakers > 0 ? numSpeakers : 1,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text('sid $i'),
                    ),
                  ),
                  onChanged: !_ttsInitialized
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() {
                            _sid = v;
                          });
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '语速',
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _speed,
                          min: 0.5,
                          max: 3.0,
                          divisions: 25,
                          label: _speed.toStringAsFixed(2),
                          onChanged: !_ttsInitialized
                              ? null
                              : (v) {
                                  setState(() {
                                    _speed = v;
                                  });
                                },
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          _speed.toStringAsFixed(2),
                          textAlign: TextAlign.end,
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _generateAndPlay,
                  child: const Text('合成并播放'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _stop,
                  child: const Text('停止'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
