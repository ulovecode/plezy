import 'package:dio/dio.dart';

import '../utils/app_logger.dart';

/// 维护一个端点列表，当其中一个端点失败时，我们可以循环使用这些端点。
class EndpointFailoverManager {
  EndpointFailoverManager(List<String> urls) {
    _setEndpoints(urls);
  }

  late List<String> _endpoints;
  int _currentIndex = 0;

  List<String> get endpoints => List.unmodifiable(_endpoints);

  String get current => _endpoints[_currentIndex];

  bool get hasFallback => _currentIndex < _endpoints.length - 1;

  /// 移动到下一个端点，返回其 URL，如果已耗尽则返回 null。
  String? moveToNext() {
    if (!hasFallback) return null;
    _currentIndex++;
    return _endpoints[_currentIndex];
  }

  /// 替换端点列表，并可选地设置当前活跃端点。
  void reset(List<String> urls, {String? currentBaseUrl}) {
    _setEndpoints(urls);
    if (currentBaseUrl != null) {
      final index = _endpoints.indexOf(currentBaseUrl);
      _currentIndex = index >= 0 ? index : 0;
    } else {
      _currentIndex = 0;
    }
  }

  void _setEndpoints(List<String> urls) {
    final sanitized = <String>[];
    final seen = <String>{};
    for (final url in urls) {
      if (url.isEmpty || seen.contains(url)) continue;
      seen.add(url);
      sanitized.add(url);
    }
    if (sanitized.isEmpty) {
      throw ArgumentError('At least one endpoint is required');
    }
    _endpoints = sanitized;
    _currentIndex = _currentIndex.clamp(0, _endpoints.length - 1);
  }
}

/// Dio 拦截器，在下一个可用端点上重试失败的请求。
class EndpointFailoverInterceptor extends Interceptor {
  EndpointFailoverInterceptor({
    required Dio dio,
    required this.endpointManager,
    required Future<void> Function(String newBaseUrl) onEndpointSwitch,
  }) : _dio = dio,
       _onEndpointSwitch = onEndpointSwitch;

  final Dio _dio;
  final EndpointFailoverManager endpointManager;
  final Future<void> Function(String newBaseUrl) _onEndpointSwitch;
  bool _isSwitching = false;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_isSwitching || !_shouldAttemptFailover(err) || !endpointManager.hasFallback) {
      handler.next(err);
      return;
    }

    final failedEndpoint = endpointManager.current;
    appLogger.w(
      'Endpoint request failed, evaluating failover',
      error: {'endpoint': failedEndpoint, 'type': err.type.name, 'statusCode': err.response?.statusCode},
      stackTrace: err.stackTrace,
    );

    final nextBaseUrl = endpointManager.moveToNext();
    if (nextBaseUrl == null) {
      appLogger.w('Endpoint failure but no fallback endpoints remain', error: {'failedEndpoint': failedEndpoint});
      handler.next(err);
      return;
    }

    _isSwitching = true;
    try {
      appLogger.i(
        'Switching Plex endpoint after request failure',
        error: {'from': failedEndpoint, 'to': nextBaseUrl, 'path': err.requestOptions.path},
      );
      await _onEndpointSwitch(nextBaseUrl);
      final response = await _retryRequest(err.requestOptions);
      appLogger.i('Endpoint failover retry succeeded', error: {'newEndpoint': nextBaseUrl});
      handler.resolve(response);
    } on DioException catch (dioError) {
      appLogger.w(
        'Endpoint failover retry failed',
        error: {'newEndpoint': nextBaseUrl, 'type': dioError.type.name, 'statusCode': dioError.response?.statusCode},
        stackTrace: dioError.stackTrace,
      );
      handler.next(dioError);
    } catch (_) {
      handler.next(err);
    } finally {
      _isSwitching = false;
    }
  }

  bool _shouldAttemptFailover(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError) {
      return true;
    }

    return false;
  }

  Future<Response<dynamic>> _retryRequest(RequestOptions requestOptions) {
    final options = Options(
      method: requestOptions.method,
      headers: requestOptions.headers,
      responseType: requestOptions.responseType,
      contentType: requestOptions.contentType,
      followRedirects: requestOptions.followRedirects,
      receiveDataWhenStatusError: requestOptions.receiveDataWhenStatusError,
      validateStatus: requestOptions.validateStatus,
      sendTimeout: requestOptions.sendTimeout,
      receiveTimeout: requestOptions.receiveTimeout,
      extra: requestOptions.extra,
      listFormat: requestOptions.listFormat,
    );

    return _dio.request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
      cancelToken: requestOptions.cancelToken,
      onSendProgress: requestOptions.onSendProgress,
      onReceiveProgress: requestOptions.onReceiveProgress,
    );
  }
}
