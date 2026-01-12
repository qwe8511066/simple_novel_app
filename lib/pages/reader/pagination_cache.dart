import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

/// 分页缓存管理器
/// 用于缓存已分页的文本内容，避免重复计算
class PaginationCache {
  static final PaginationCache _instance = PaginationCache._internal();
  factory PaginationCache() => _instance;
  PaginationCache._internal();

  final Map<String, List<List<String>>> _cache = {};
  final Map<String, String> _fileHashes = {};

  /// 获取缓存文件目录
  Future<Directory> _getCacheDir() async {
    final tempDir = await Directory.systemTemp.createTemp('novel_reader_cache');
    return tempDir;
  }

  /// 生成文件的哈希值，用于缓存键
  Future<String> _getFileHash(File file) async {
    final content = await file.readAsString();
    return content.hashCode.toString();
  }

  /// 检查是否有有效的缓存
  Future<bool> hasValidCache(String fileId, File sourceFile) async {
    // 检查内存缓存
    if (_cache.containsKey(fileId)) {
      // 检查文件是否被修改
      final currentHash = await _getFileHash(sourceFile);
      final cachedHash = _fileHashes[fileId];
      return cachedHash != null && currentHash == cachedHash;
    }

    // 检查磁盘缓存
    final cacheFile = await _getCacheFile(fileId);
    if (await cacheFile.exists()) {
      // 验证缓存文件与源文件的一致性
      final currentHash = await _getFileHash(sourceFile);
      final cachedHash = await _readHashFromFile(cacheFile);
      return currentHash == cachedHash;
    }

    return false;
  }

  /// 从缓存获取分页数据
  Future<List<List<String>>?> getCachedPages(String fileId, File sourceFile) async {
    // 首先检查内存缓存
    if (_cache.containsKey(fileId)) {
      final currentHash = await _getFileHash(sourceFile);
      final cachedHash = _fileHashes[fileId];
      if (cachedHash != null && currentHash == cachedHash) {
        return _cache[fileId];
      }
    }

    // 检查磁盘缓存
    final cacheFile = await _getCacheFile(fileId);
    if (await cacheFile.exists()) {
      final currentHash = await _getFileHash(sourceFile);
      final cachedHash = await _readHashFromFile(cacheFile);
      if (currentHash == cachedHash) {
        try {
          final content = await cacheFile.readAsString();
          final data = jsonDecode(content) as Map<String, dynamic>;
          final pagesData = data['pages'] as List;
          final pages = <List<String>>[];

          for (final pageData in pagesData) {
            final page = (pageData as List).map((e) => e as String).toList();
            pages.add(page);
          }

          // 同时保存到内存缓存
          _cache[fileId] = pages;
          _fileHashes[fileId] = currentHash;

          return pages;
        } catch (e) {
          // 缓存文件损坏，删除它
          await cacheFile.delete();
          return null;
        }
      }
    }

    return null;
  }

  /// 保存分页数据到缓存
  Future<void> savePagesToCache(String fileId, File sourceFile, List<List<String>> pages) async {
    try {
      // 保存到内存缓存
      _cache[fileId] = pages;
      final fileHash = await _getFileHash(sourceFile);
      _fileHashes[fileId] = fileHash;

      // 保存到磁盘缓存
      final cacheFile = await _getCacheFile(fileId);
      final data = {
        'hash': fileHash,
        'pages': pages.map((page) => page).toList(),
      };
      await cacheFile.writeAsString(jsonEncode(data));
    } catch (e) {
      print('保存缓存失败: $e');
    }
  }

  /// 获取缓存文件路径
  Future<File> _getCacheFile(String fileId) async {
    final cacheDir = await _getCacheDir();
    return File(path.join(cacheDir.path, '${fileId}_pagination_cache.json'));
  }

  /// 从缓存文件中读取哈希值
  Future<String> _readHashFromFile(File cacheFile) async {
    try {
      final content = await cacheFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      return data['hash'] as String;
    } catch (e) {
      return '';
    }
  }

  /// 清除指定文件的缓存
  Future<void> clearCache(String fileId) async {
    _cache.remove(fileId);
    _fileHashes.remove(fileId);
    
    final cacheFile = await _getCacheFile(fileId);
    if (await cacheFile.exists()) {
      await cacheFile.delete();
    }
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    _cache.clear();
    _fileHashes.clear();
    
    final cacheDir = await _getCacheDir();
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
  }
}