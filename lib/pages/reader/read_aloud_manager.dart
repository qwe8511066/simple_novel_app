import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../providers/novel_provider.dart';
import '../../services/audio_player_service.dart';
import '../../services/sherpa_tts_service.dart';

class ReadAloudManager {
  ReadAloudManager({
    required NovelProvider Function() novelProvider,
    required SherpaTtsService ttsService,
    required AudioPlayerService audioPlayerService,
    required int Function() totalPages,
    required List<String> Function(int pageIndex) pageParagraphs,
    required Future<void> Function(int nextPageIndex) turnToPage,
    Future<void> Function(int pageIndex)? ensurePageAvailable,
    int prefetchNextPages = 2,
  })  : _novelProvider = novelProvider,
        _ttsService = ttsService,
        _audioPlayerService = audioPlayerService,
        _totalPages = totalPages,
        _pageParagraphs = pageParagraphs,
        _turnToPage = turnToPage,
        _ensurePageAvailable = ensurePageAvailable,
        _prefetchNextPages = prefetchNextPages;

  final NovelProvider Function() _novelProvider;
  final SherpaTtsService _ttsService;
  final AudioPlayerService _audioPlayerService;
  final int Function() _totalPages;
  final List<String> Function(int pageIndex) _pageParagraphs;
  final Future<void> Function(int nextPageIndex) _turnToPage;
  final Future<void> Function(int pageIndex)? _ensurePageAvailable;
  final int _prefetchNextPages;

  bool _ttsInitialized = false;

  bool _readingModeEnabled = false;
  bool _isReading = false;
  int _readingPageIndex = -1;
  int _readingParagraphIndex = -1;
  int _readingSessionId = 0;
  Future<void>? _readingTask;
  Timer? _resumeTimer;

  final ValueNotifier<int> _highlightTick = ValueNotifier<int>(0);
  ValueNotifier<int> get highlightTick => _highlightTick;

  bool get isReading => _isReading || _audioPlayerService.isPlaying;
  bool get readingModeEnabled => _readingModeEnabled;
  int get readingPageIndex => _readingPageIndex;
  int get readingParagraphIndex => _readingParagraphIndex;

  final Map<String, String> _ttsCache = <String, String>{};
  final Map<String, Future<String?>> _ttsInFlight = <String, Future<String?>>{};
  final List<String> _ttsCacheOrder = <String>[];
  static const int _ttsCacheMaxEntries = 24;

  static const int _prefetchMaxParagraphsPerPage = 3;
  static const int _prefetchTriggerParagraphIndex = 2;

  int? _lastSid;
  double? _lastSpeed;

  void dispose() {
    stop();
    for (final p in _ttsCache.values) {
      try {
        final f = File(p);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (_) {}
    }
    _ttsCache.clear();
    _ttsCacheOrder.clear();
    _highlightTick.dispose();
  }

  Future<bool> _ensureTtsInitialized() async {
    if (_ttsInitialized) return true;
    final ok = await _ttsService.initialize();
    _ttsInitialized = ok;
    return ok;
  }

  Future<void> stop() async {
    _resumeTimer?.cancel();
    _resumeTimer = null;

    if (!_isReading && !_audioPlayerService.isPlaying) {
      _readingModeEnabled = false;
      return;
    }

    _readingSessionId++;
    _readingModeEnabled = false;
    _isReading = false;
    _readingPageIndex = -1;
    _readingParagraphIndex = -1;
    _highlightTick.value++;
    await _audioPlayerService.stop();

    final task = _readingTask;
    if (task != null) {
      try {
        await task;
      } catch (_) {}
    }
  }

  Future<void> startPage(int pageIndex) async {
    await stop();

    final sessionId = ++_readingSessionId;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _readingModeEnabled = true;
    _isReading = true;
    _readingPageIndex = pageIndex;
    _readingParagraphIndex = -1;
    _highlightTick.value++;

    _readingTask = Future<void>(() async {
      final ensure = _ensurePageAvailable;
      if (ensure != null) {
        try {
          await ensure(pageIndex);
        } catch (_) {}
      }
      final paragraphs = _pageParagraphs(pageIndex);
      if (paragraphs.isEmpty) return;

      final ok = await _ensureTtsInitialized();
      if (!ok) return;

      final novelProvider = _novelProvider();
      final maxSid = (_ttsService.numSpeakers > 0) ? (_ttsService.numSpeakers - 1) : 0;
      final sid = novelProvider.ttsSid.clamp(0, maxSid);
      final speed = novelProvider.ttsSpeed;

      _lastSid = sid;
      _lastSpeed = speed;

      final synthQueue = List<Future<String?>>.generate(
        paragraphs.length,
        (i) async => null,
      );
      var scheduledUntil = -1;

      void scheduleUpTo(int index) {
        final target = index.clamp(0, paragraphs.length - 1);
        while (scheduledUntil < target) {
          scheduledUntil++;
          final text = paragraphs[scheduledUntil];
          // 检查是否已缓存，避免重复合成
          final key = _ttsCacheKey(text, sid: sid, speed: speed);
          if (_ttsCache.containsKey(key)) {
            synthQueue[scheduledUntil] = Future.value(_ttsCache[key]!);
          } else {
            synthQueue[scheduledUntil] = _synthesizeWithCache(text, sid: sid, speed: speed);
          }
        }
      }

      // 只合成第一个段落，其余的在后端逐步合成
      scheduleUpTo(0);

      try {
        await synthQueue[0];
      } catch (_) {}

      for (var i = 0; i < paragraphs.length; i++) {
        if (sessionId != _readingSessionId) return;

        _readingParagraphIndex = i;
        _highlightTick.value++;

        // 提前合成下一个段落（避免播放时等待）
        if (i + 1 < paragraphs.length) {
          scheduleUpTo(i + 1);
        }

        String? wavPath;
        try {
          wavPath = await synthQueue[i];
        } catch (_) {
          wavPath = null;
        }

        if (sessionId != _readingSessionId) return;
        if (wavPath == null || wavPath.isEmpty) continue;

        await _audioPlayerService.playWavFileAndWait(wavPath);

        // Prefetch is CPU-heavy (runs on main isolate). Trigger it only after we've
        // already started reading a bit, to avoid causing a pause right after page turn.
        final shouldTriggerPrefetch =
            _prefetchNextPages > 0 && i == _prefetchTriggerParagraphIndex;
        if (shouldTriggerPrefetch) {
          unawaited(Future<void>.delayed(Duration.zero, () async {
            if (sessionId != _readingSessionId) return;
            if (!_readingModeEnabled) return;
            if (_readingPageIndex != pageIndex) return;
            await _prefetchTargetPage(
              baseSessionId: sessionId,
              currentPageIndex: pageIndex,
              sid: sid,
              speed: speed,
            );
          }));
        }
      }
    }).whenComplete(() {
      if (sessionId != _readingSessionId) return;

      final shouldContinue = _readingModeEnabled;
      _isReading = false;
      _readingPageIndex = -1;
      _readingParagraphIndex = -1;
      _highlightTick.value++;

      if (shouldContinue) {
        Future<void>(() async {
          final ensure = _ensurePageAvailable;
          final next = pageIndex + 1;
          if (ensure != null) {
            try {
              await ensure(next);
            } catch (_) {}
          }
          if (next >= _totalPages()) return;
          if (sessionId != _readingSessionId) return;
          if (!_readingModeEnabled) return;

          final sid = _lastSid;
          final speed = _lastSpeed;
          if (sid != null && speed != null) {
            await _ensureNextPageHeadReady(
              baseSessionId: sessionId,
              pageIndex: next,
              sid: sid,
              speed: speed,
            );
          }
          await _turnToPage(next);
          await startPage(next);
        });
      }
    });

    await _readingTask;
  }

  Future<void> handlePageChanged(int index) async {
    if (!_readingModeEnabled) return;

    final keepReadingMode = _readingModeEnabled;
    await _audioPlayerService.stop();
    if (keepReadingMode) {
      _readingSessionId++;
      _isReading = false;
      _readingPageIndex = -1;
      _readingParagraphIndex = -1;
      _highlightTick.value++;
      
      // 直接开始新页面，利用缓存机制避免重新合成
      await startPage(index);
    }
  }

  Future<void> handleManualPageChanged(
    int index, {
    Duration resumeDelay = const Duration(seconds: 2),
  }) async {
    if (!_readingModeEnabled) return;

    _readingSessionId++;
    final token = _readingSessionId;
    _resumeTimer?.cancel();
    _resumeTimer = null;

    await _audioPlayerService.stop();

    _isReading = false;
    _readingPageIndex = -1;
    _readingParagraphIndex = -1;
    _highlightTick.value++;

    _resumeTimer = Timer(resumeDelay, () {
      if (token != _readingSessionId) return;
      if (!_readingModeEnabled) return;
      Future<void>(() async {
        await startPage(index);
      });
    });
  }

  Future<void> _prefetchTargetPage({
    required int baseSessionId,
    required int currentPageIndex,
    required int sid,
    required double speed,
  }) async {
    final targetPageIndex = (currentPageIndex + _prefetchNextPages).clamp(0, _totalPages() - 1);
    if (targetPageIndex <= currentPageIndex) return;
    if (baseSessionId != _readingSessionId) return;
    if (!_readingModeEnabled) return;

    final paragraphs = _pageParagraphs(targetPageIndex);
    var prefetchedCount = 0;
    for (final text in paragraphs) {
      if (baseSessionId != _readingSessionId) return;
      if (!_readingModeEnabled) return;

      if (prefetchedCount >= _prefetchMaxParagraphsPerPage) return;

      final key = _ttsCacheKey(text, sid: sid, speed: speed);
      if (_ttsCache.containsKey(key)) continue;

      // Cooperative yield: TTS generate is CPU-heavy and runs on main isolate.
      // Yielding between paragraphs helps avoid blocking current playback scheduling.
      await Future<void>.delayed(Duration.zero);
      prefetchedCount++;
      unawaited(_synthesizeWithCache(text, sid: sid, speed: speed).catchError((_) => null));
    }
  }

  Future<void> _ensureNextPageHeadReady({
    required int baseSessionId,
    required int pageIndex,
    required int sid,
    required double speed,
  }) async {
    if (baseSessionId != _readingSessionId) return;
    if (!_readingModeEnabled) return;

    final paragraphs = _pageParagraphs(pageIndex);
    if (paragraphs.isEmpty) return;

    final head = paragraphs.first;
    try {
      await _synthesizeWithCache(head, sid: sid, speed: speed);
    } catch (_) {}
  }

  void unawaited(Future<void> f) {
    // Helper to fire-and-forget a Future without awaiting.
    // This mirrors the async_helper package's unawaited.
    f.catchError((_) {});
  }

  String _normalizeCacheText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _ttsCacheKey(String text, {required int sid, required double speed}) {
    final normalized = _normalizeCacheText(text);
    return '$sid|$speed|$normalized';
  }

  void _putTtsCachePath(String key, String path) {
    if (_ttsCache.containsKey(key)) return;
    _ttsCache[key] = path;
    _ttsCacheOrder.add(key);
    if (_ttsCacheOrder.length > _ttsCacheMaxEntries) {
      final oldest = _ttsCacheOrder.removeAt(0);
      final p = _ttsCache.remove(oldest);
      if (p != null) {
        try {
          final f = File(p);
          if (f.existsSync()) {
            f.deleteSync();
          }
        } catch (_) {}
      }
    }
  }

  Future<String?> _synthesizeWithCache(
    String text, {
    required int sid,
    required double speed,
  }) async {
    final key = _ttsCacheKey(text, sid: sid, speed: speed);
    final cached = _ttsCache[key];
    if (cached != null) return cached;

    final inflight = _ttsInFlight[key];
    if (inflight != null) return inflight;

    final f = Future<String?>(() async {
      final path = await _ttsService.synthesizeToWavFile(
        _normalizeCacheText(text),
        sid: sid,
        speed: speed,
      );
      if (path != null && path.isNotEmpty) {
        _putTtsCachePath(key, path);
      }
      return path;
    });

    _ttsInFlight[key] = f;
    try {
      return await f;
    } finally {
      final existing = _ttsInFlight[key];
      if (identical(existing, f)) {
        _ttsInFlight.remove(key);
      }
    }
  }
}
