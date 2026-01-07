import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart';
import 'package:saf_stream/saf_stream.dart';

/// 为 Android 处理存储访问框架 (SAF) 操作
class SafStorageService {
  static SafStorageService? _instance;
  static SafStorageService get instance => _instance ??= SafStorageService._();
  SafStorageService._();

  final SafUtil _safUtil = SafUtil();
  final SafStream _safStream = SafStream();

  /// 检查 SAF 是否可用 (仅限 Android)
  bool get isAvailable => Platform.isAndroid;

  /// 使用 SAF 选择目录
  /// 返回 content:// URI，如果取消则返回 null
  Future<String?> pickDirectory() async {
    if (!isAvailable) return null;
    try {
      // 选择具有持久写入权限的目录
      final doc = await _safUtil.pickDirectory(writePermission: true, persistablePermission: true);
      return doc?.uri;
    } catch (e) {
      debugPrint('SAF pickDirectory 错误: $e');
      return null;
    }
  }

  /// 检查我们是否对某个 URI 拥有持久访问权限
  Future<bool> hasPersistedPermission(String contentUri) async {
    if (!isAvailable) return false;
    try {
      return await _safUtil.hasPersistedPermission(contentUri, checkRead: true, checkWrite: true);
    } catch (e) {
      debugPrint('SAF hasPersistedPermission 错误: $e');
      return false;
    }
  }

  /// 获取 URI 的文档文件信息
  Future<SafDocumentFile?> getDocumentFile(String contentUri, {bool isDir = true}) async {
    if (!isAvailable) return null;
    try {
      return await _safUtil.documentFileFromUri(contentUri, isDir);
    } catch (e) {
      debugPrint('SAF getDocumentFile 错误: $e');
      return null;
    }
  }

  /// 在 SAF 目录中创建子目录
  /// 返回创建的目录的 URI
  Future<String?> createDirectory(String parentUri, String name) async {
    if (!isAvailable) return null;
    try {
      final result = await _safUtil.mkdirp(parentUri, [name]);
      return result.uri;
    } catch (e) {
      debugPrint('SAF createDirectory 错误: $e');
      return null;
    }
  }

  /// 列出 SAF 目录中的文件
  Future<List<SafDocumentFile>> listDirectory(String contentUri) async {
    if (!isAvailable) return [];
    try {
      return await _safUtil.list(contentUri);
    } catch (e) {
      debugPrint('SAF listDirectory 错误: $e');
      return [];
    }
  }

  /// 获取 SAF 目录中的子文件/目录
  Future<SafDocumentFile?> getChild(String parentUri, String name) async {
    if (!isAvailable) return null;
    try {
      return await _safUtil.child(parentUri, [name]);
    } catch (e) {
      debugPrint('SAF getChild 错误: $e');
      return null;
    }
  }

  /// 在 SAF 中删除文件或目录
  Future<bool> delete(String contentUri, {bool isDir = false}) async {
    if (!isAvailable) return false;
    try {
      await _safUtil.delete(contentUri, isDir);
      return true;
    } catch (e) {
      debugPrint('SAF delete 错误: $e');
      return false;
    }
  }

  /// 获取 SAF URI 的显示名称 (用于 UI)
  Future<String?> getDisplayName(String contentUri) async {
    if (!isAvailable) return null;
    try {
      final doc = await _safUtil.documentFileFromUri(contentUri, true);
      return doc?.name;
    } catch (e) {
      debugPrint('SAF getDisplayName 错误: $e');
      return null;
    }
  }

  /// 在 SAF 目录中创建嵌套目录
  /// 返回最深层目录的 URI
  Future<String?> createNestedDirectories(String parentUri, List<String> pathComponents) async {
    if (!isAvailable) return null;
    try {
      final result = await _safUtil.mkdirp(parentUri, pathComponents);
      return result.uri;
    } catch (e) {
      debugPrint('SAF createNestedDirectories 错误: $e');
      return null;
    }
  }

  /// 使用原生复制将文件从本地存储复制到 SAF 目录
  /// 返回复制后文件的 SAF URI，失败则返回 null
  Future<String?> copyFileToSaf(
    String sourceFilePath,
    String targetDirectoryUri,
    String fileName,
    String mimeType,
  ) async {
    if (!isAvailable) return null;

    try {
      final sourceFile = File(sourceFilePath);
      if (!await sourceFile.exists()) {
        debugPrint('SAF copyFileToSaf: 源文件不存在');
        return null;
      }

      // 使用 pasteLocalFile 进行原生端复制 (无 method channel 流式传输)
      // 这对大文件更有效并可避免挂起
      final result = await _safStream
          .pasteLocalFile(sourceFilePath, targetDirectoryUri, fileName, mimeType, overwrite: true)
          .timeout(const Duration(minutes: 30), onTimeout: () => throw TimeoutException('SAF 复制超时'));

      debugPrint('SAF copyFileToSaf: 成功复制到 ${result.uri}');
      return result.uri.toString();
    } on TimeoutException catch (e) {
      debugPrint('SAF copyFileToSaf 超时: $e');
      return null;
    } catch (e) {
      debugPrint('SAF copyFileToSaf 错误: $e');
      return null;
    }
  }

  /// 直接向 SAF 文件写入字节
  /// 返回创建文件的 SAF URI，失败则返回 null
  Future<String?> writeFileBytes(String directoryUri, String fileName, String mimeType, Uint8List bytes) async {
    if (!isAvailable) return null;
    try {
      final result = await _safStream.writeFileBytes(directoryUri, fileName, mimeType, bytes);
      return result.uri.toString();
    } catch (e) {
      debugPrint('SAF writeFileBytes 错误: $e');
      return null;
    }
  }

  /// 从 SAF 文件读取字节
  Future<Uint8List?> readFileBytes(String fileUri) async {
    if (!isAvailable) return null;
    try {
      return await _safStream.readFileBytes(fileUri);
    } catch (e) {
      debugPrint('SAF readFileBytes 错误: $e');
      return null;
    }
  }

  /// 检查 SAF 目录中是否存在文件
  Future<bool> fileExists(String parentUri, String fileName) async {
    if (!isAvailable) return false;
    try {
      final child = await _safUtil.child(parentUri, [fileName]);
      return child != null;
    } catch (e) {
      debugPrint('SAF fileExists 错误: $e');
      return false;
    }
  }

  /// 获取可被 MediaStore/媒体播放器读取的文件内容 URI
  /// 对于 SAF 文件，返回与输入相同的 URI (content:// URI 已经可读)
  String getReadableUri(String safUri) => safUri;
}
