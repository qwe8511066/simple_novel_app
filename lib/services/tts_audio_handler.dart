import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

TtsAudioHandler? ttsAudioHandler;

Future<TtsAudioHandler>? _ttsAudioServiceInitFuture;

Future<void> initTtsAudioService() async {
  await ensureTtsAudioServiceReady();
}

bool _ttsAudioServiceInitialized = false;

Future<TtsAudioHandler> ensureTtsAudioServiceReady() async {
  final existing = ttsAudioHandler;
  if (_ttsAudioServiceInitialized && existing != null) return existing;

  final inflight = _ttsAudioServiceInitFuture;
  if (inflight != null) return inflight;

  final future = AudioService.init(
    builder: () => TtsAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.example.app.tts',
      androidNotificationChannelName: '简单小说朗读',
      androidNotificationIcon: 'drawable/ic_stat_tts',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );

  _ttsAudioServiceInitFuture = future;
  try {
    final handler = await future;
    ttsAudioHandler = handler;
    _ttsAudioServiceInitialized = true;
    return handler;
  } catch (e) {
    _ttsAudioServiceInitialized = false;
    ttsAudioHandler = null;
    rethrow;
  } finally {
    _ttsAudioServiceInitFuture = null;
  }
}

class TtsAudioHandler extends BaseAudioHandler with SeekHandler {
  TtsAudioHandler() {
    _player.playerStateStream.listen((state) {
      _broadcastState(state);
    });

    _player.processingStateStream.listen((processing) {
      if (processing == ProcessingState.completed) {
        // Keep the service alive (and notification visible) between short segments.
        // If we let it go idle, Android may tear down the foreground notification.
        unawaited(_player.pause());
        unawaited(_player.seek(Duration.zero));
        _broadcastState(_player.playerState);
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();

  Future<void> playWavFileAndWait(
    String filePath, {
    String? title,
    String? artist,
  }) async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());

    mediaItem.add(
      MediaItem(
        id: filePath,
        title: title ?? '朗读',
        artist: artist,
      ),
    );

    await _player.stop();
    await _player.setAudioSource(AudioSource.uri(Uri.file(filePath)));
    await _player.play();

    await _player.processingStateStream.firstWhere(
      (s) => s == ProcessingState.completed || s == ProcessingState.idle,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    // Paragraph-level skipping is managed by ReadAloudManager.
    // We expose the action in the notification but keep it as no-op for now.
  }

  @override
  Future<void> skipToPrevious() async {
    // Paragraph-level skipping is managed by ReadAloudManager.
    // We expose the action in the notification but keep it as no-op for now.
  }

  void _broadcastState(PlayerState playerState) {
    final processingState = playerState.processingState;

    AudioProcessingState audioProcessingState;
    switch (processingState) {
      case ProcessingState.idle:
        // Avoid reporting idle to keep the media notification alive.
        audioProcessingState = AudioProcessingState.ready;
        break;
      case ProcessingState.loading:
        audioProcessingState = AudioProcessingState.loading;
        break;
      case ProcessingState.buffering:
        audioProcessingState = AudioProcessingState.buffering;
        break;
      case ProcessingState.ready:
        audioProcessingState = AudioProcessingState.ready;
        break;
      case ProcessingState.completed:
        // Treat completed as ready so the notification doesn't vanish between segments.
        audioProcessingState = AudioProcessingState.ready;
        break;
    }

    playbackState.add(
      playbackState.value.copyWith(
        controls: <MediaControl>[
          MediaControl.skipToPrevious,
          playerState.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const <MediaAction>{
          MediaAction.seek,
        },
        androidCompactActionIndices: const <int>[0, 1, 2],
        processingState: audioProcessingState,
        playing: playerState.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: 0,
      ),
    );
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
