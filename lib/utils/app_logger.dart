import 'package:logger/logger.dart';

import 'log_redaction_manager.dart';

/// 根据已知值脱敏日志消息中的敏感信息。
String _redactSensitiveData(String message) {
  var redacted = LogRedactionManager.redact(message);

  // 对于无法提前追踪的敏感字段进行兜底处理。
  redacted = redacted.replaceAllMapped(
    RegExp(r'([Aa]uthorization[=:]\s*)([^\s,]+)'),
    (match) => '${match.group(1)}[REDACTED]',
  );

  redacted = redacted.replaceAllMapped(
    RegExp(r'([Pp]assword[=:]\s*)([^\s&,;]+)'),
    (match) => '${match.group(1)}[REDACTED]',
  );

  return redacted;
}

/// 表示存储在内存中的单条日志条目
class LogEntry {
  final DateTime timestamp;
  final Level level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({required this.timestamp, required this.level, required this.message, this.error, this.stackTrace});

  /// 估算此日志条目占用的内存大小（以字节为单位）
  int get estimatedSize {
    int size = 0;
    // DateTime: ~8 字节
    size += 8;
    // Level 枚举: ~4 字节
    size += 4;
    // 消息字符串: 每个字符 2 字节 (UTF-16)
    size += message.length * 2;
    // 错误字符串: 如果存在，每个字符 2 字节
    if (error != null) {
      size += error.toString().length * 2;
    }
    // 堆栈轨迹字符串: 如果存在，每个字符 2 字节
    if (stackTrace != null) {
      size += stackTrace.toString().length * 2;
    }
    return size;
  }
}

/// 自定义日志输出，使用循环缓冲区在内存中存储日志
class MemoryLogOutput extends LogOutput {
  static const int maxLogSizeBytes = 5 * 1024 * 1024; // 5 MB
  static final List<LogEntry> _logs = [];
  static int _currentSize = 0;

  /// 获取所有存储的日志（最新的排在前面）
  static List<LogEntry> getLogs() => List.unmodifiable(_logs.reversed);

  /// 清除所有存储的日志
  static void clearLogs() {
    _logs.clear();
    _currentSize = 0;
  }

  /// 获取当前日志缓冲区的大小（字节）
  static int getCurrentSize() => _currentSize;

  /// 获取当前日志缓冲区的大小（MB）
  static double getCurrentSizeMB() => _currentSize / (1024 * 1024);

  @override
  void output(OutputEvent event) {
    // 从日志事件中提取相关信息
    for (var line in event.lines) {
      final logEntry = LogEntry(timestamp: DateTime.now(), level: event.level, message: _redactSensitiveData(line));

      _logs.add(logEntry);
      _currentSize += logEntry.estimatedSize;

      // 维持缓冲区大小限制（移除最旧的条目）
      while (_currentSize > maxLogSizeBytes && _logs.isNotEmpty) {
        final removed = _logs.removeAt(0);
        _currentSize -= removed.estimatedSize;
      }
    }
  }
}

/// 自定义日志打印器，同时存储错误和堆栈轨迹信息
class MemoryAwareLogPrinter extends LogPrinter {
  final LogPrinter _wrappedPrinter;

  MemoryAwareLogPrinter(this._wrappedPrinter);

  @override
  List<String> log(LogEvent event) {
    // 如果可用，存储带有错误和堆栈轨迹的日志
    final message = _redactSensitiveData(event.message.toString());
    final error = event.error != null ? _redactSensitiveData(event.error.toString()) : null;

    final logEntry = LogEntry(
      timestamp: DateTime.now(),
      level: event.level,
      message: message,
      error: error,
      stackTrace: event.stackTrace,
    );

    MemoryLogOutput._logs.add(logEntry);
    MemoryLogOutput._currentSize += logEntry.estimatedSize;

    // 维持缓冲区大小限制（移除最旧的条目）
    while (MemoryLogOutput._currentSize > MemoryLogOutput.maxLogSizeBytes && MemoryLogOutput._logs.isNotEmpty) {
      final removed = MemoryLogOutput._logs.removeAt(0);
      MemoryLogOutput._currentSize -= removed.estimatedSize;
    }

    // 委托给包装的打印器进行控制台输出
    return _wrappedPrinter.log(event);
  }
}

/// 自定义生产环境过滤器，即使在发布模式下也遵循我们的级别设置
class ProductionFilter extends LogFilter {
  Level _currentLevel = Level.debug;

  void setLevel(Level level) {
    _currentLevel = level;
  }

  @override
  bool shouldLog(LogEvent event) {
    return event.level.value >= _currentLevel.value;
  }
}

/// 全局过滤器实例
final _productionFilter = ProductionFilter();

/// 应用程序的中心化日志实例。
///
/// 用法:
/// ```dart
/// import 'package:plezy/utils/app_logger.dart';
///
/// appLogger.d('调试消息');
/// appLogger.i('信息消息');
/// appLogger.w('警告消息');
/// appLogger.e('错误消息', error: e, stackTrace: stackTrace);
/// ```
Logger appLogger = Logger(
  printer: MemoryAwareLogPrinter(SimplePrinter()),
  filter: _productionFilter,
  level: Level.debug,
);

/// 根据调试设置动态更新日志记录器的级别
/// 重新创建日志记录器实例以确保它在发布模式下也能工作
void setLoggerLevel(bool debugEnabled) {
  final newLevel = debugEnabled ? Level.debug : Level.info;

  // 更新过滤器级别
  _productionFilter.setLevel(newLevel);

  // 使用新级别重新创建日志记录器实例
  // 这确保了它在发布模式下也能工作，因为在发布模式下 Logger.level 可能会被优化掉
  appLogger = Logger(printer: MemoryAwareLogPrinter(SimplePrinter()), filter: _productionFilter, level: newLevel);

  // 同时设置静态级别以保持一致性
  Logger.level = newLevel;
}
