import 'dart:convert';
import 'package:flutter/services.dart';

/// 用于在 ISO 639-1（2 位字母）和 ISO 639-2（3 位字母）语言代码之间进行转换的辅助类
class LanguageCodes {
  static Map<String, dynamic>? _codes;

  /// 从 JSON 加载语言代码
  static Future<void> initialize() async {
    if (_codes != null) return;

    final jsonString = await rootBundle.loadString('lib/data/iso_639_codes.json');
    _codes = json.decode(jsonString) as Map<String, dynamic>;
  }

  /// 获取语言代码的所有可能变体
  /// 处理 ISO 639-1（2 位字母）和 ISO 639-2（3 位字母）代码
  /// 返回用于检查轨道语言的代码列表
  static List<String> getVariations(String languageCode) {
    if (_codes == null) {
      throw StateError('LanguageCodes 未初始化。请先调用 initialize()。');
    }

    final normalized = languageCode.toLowerCase().trim();
    final variations = <String>{normalized}; // 使用 Set 避免重复

    // 检查是否为 2 位代码 (ISO 639-1)
    if (_codes!.containsKey(normalized)) {
      final entry = _codes![normalized] as Map<String, dynamic>;

      // 添加 639-1 代码
      if (entry.containsKey('639-1')) {
        variations.add((entry['639-1'] as String).toLowerCase());
      }

      // 添加 639-2 代码
      if (entry.containsKey('639-2')) {
        variations.add((entry['639-2'] as String).toLowerCase());
      }

      // 如果存在 639-2/B 代码（书目变体），则添加它
      if (entry.containsKey('639-2/B')) {
        variations.add((entry['639-2/B'] as String).toLowerCase());
      }
    } else {
      // 可能是 3 位代码，进行搜索
      for (var entry in _codes!.values) {
        final entryMap = entry as Map<String, dynamic>;

        // 检查此条目是否包含我们的代码作为 639-2 或 639-2/B
        final code6392 = entryMap['639-2'] as String?;
        final code6392B = entryMap['639-2/B'] as String?;

        if (code6392?.toLowerCase() == normalized || code6392B?.toLowerCase() == normalized) {
          // 添加此条目的所有变体
          if (entryMap.containsKey('639-1')) {
            variations.add((entryMap['639-1'] as String).toLowerCase());
          }
          if (code6392 != null) {
            variations.add(code6392.toLowerCase());
          }
          if (code6392B != null) {
            variations.add(code6392B.toLowerCase());
          }
          break;
        }
      }
    }

    return variations.toList();
  }

  /// 根据语言代码获取语言的英文名称
  static String? getLanguageName(String languageCode) {
    if (_codes == null) return null;

    final normalized = languageCode.toLowerCase().trim();

    // 检查是否为 2 位代码
    if (_codes!.containsKey(normalized)) {
      final entry = _codes![normalized] as Map<String, dynamic>;
      return entry['name'] as String?;
    }

    // 搜索 3 位代码
    for (var entry in _codes!.values) {
      final entryMap = entry as Map<String, dynamic>;
      final code6392 = entryMap['639-2'] as String?;
      final code6392B = entryMap['639-2/B'] as String?;

      if (code6392?.toLowerCase() == normalized || code6392B?.toLowerCase() == normalized) {
        return entryMap['name'] as String?;
      }
    }

    return null;
  }
}
