import 'package:dio/dio.dart';
import '../i18n/strings.g.dart';
import 'app_logger.dart';

/// 共享辅助函数，用于将网络错误转换为用户友好的消息。
String mapDioErrorToMessage(DioException error, {required String context}) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
      return t.errors.connectionTimeout(context: context);
    case DioExceptionType.connectionError:
      return t.errors.connectionFailed;
    default:
      appLogger.e('Error loading $context', error: error);
      return t.errors.failedToLoad(context: context, error: error.message ?? t.common.unknown);
  }
}

/// 针对意外错误的通用回退处理。
String mapUnexpectedErrorToMessage(dynamic error, {required String context}) {
  appLogger.e('Unexpected error in $context', error: error);
  return t.errors.failedToLoad(context: context, error: error.toString());
}
