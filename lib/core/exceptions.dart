class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  AppException({
    required this.message,
    this.code,
    this.details,
  });

  @override
  String toString() => 'AppException: $message ${code != null ? '($code)' : ''}';
}

class OpenAIException extends AppException {
  final int? statusCode;
  final String? errorType;

  OpenAIException({
    required String message,
    this.statusCode,
    this.errorType,
    String? code,
    dynamic details,
  }) : super(
          message: message,
          code: code,
          details: details,
        );

  factory OpenAIException.fromDioError(dynamic error) {
    if (error.response != null) {
      final statusCode = error.response?.statusCode ?? 0;
      final data = error.response?.data;
      
      String message = 'Unknown API error';
      String? errorType;
      
      if (data != null && data is Map) {
        if (data['error'] != null) {
          message = data['error']['message'] ?? message;
          errorType = data['error']['type'];
        }
      }
      
      // Handle specific status codes
      switch (statusCode) {
        case 401:
          return OpenAIException(
            message: 'Invalid API key. Please check your OpenAI configuration.',
            statusCode: statusCode,
            errorType: 'authentication_error',
            code: 'AUTH_ERROR',
          );
        case 429:
          return OpenAIException(
            message: 'Rate limit exceeded. Please try again later.',
            statusCode: statusCode,
            errorType: 'rate_limit_error',
            code: 'RATE_LIMIT',
          );
        case 402:
          return OpenAIException(
            message: 'Insufficient credits. Please check your OpenAI account.',
            statusCode: statusCode,
            errorType: 'insufficient_credits',
            code: 'INSUFFICIENT_CREDITS',
          );
        case 500:
        case 502:
        case 503:
          return OpenAIException(
            message: 'OpenAI service temporarily unavailable. Please try again.',
            statusCode: statusCode,
            errorType: 'server_error',
            code: 'SERVER_ERROR',
          );
        default:
          return OpenAIException(
            message: message,
            statusCode: statusCode,
            errorType: errorType,
            code: 'API_ERROR',
          );
      }
    } else if (error.type != null) {
      // Network errors
      String message = 'Network error occurred';
      String code = 'NETWORK_ERROR';
      
      switch (error.type) {
        case DioErrorType.connectionTimeout:
          message = 'Connection timeout. Please check your internet connection.';
          code = 'TIMEOUT';
          break;
        case DioErrorType.receiveTimeout:
          message = 'Response timeout. The server took too long to respond.';
          code = 'TIMEOUT';
          break;
        case DioErrorType.connectionError:
          message = 'Unable to connect to OpenAI servers. Please check your internet connection.';
          code = 'CONNECTION_ERROR';
          break;
        default:
          break;
      }
      
      return OpenAIException(
        message: message,
        code: code,
        details: error.message,
      );
    }
    
    return OpenAIException(
      message: error.toString(),
      code: 'UNKNOWN_ERROR',
    );
  }

  bool get isRetryable {
    if (statusCode == null) return true; // Network errors are retryable
    return statusCode! >= 500 || statusCode == 429;
  }
}

class ImageGenerationException extends OpenAIException {
  ImageGenerationException({
    required String message,
    int? statusCode,
    String? errorType,
    String? code,
    dynamic details,
  }) : super(
          message: message,
          statusCode: statusCode,
          errorType: errorType,
          code: code ?? 'IMAGE_GENERATION_ERROR',
          details: details,
        );
}

class ContentModerationException extends OpenAIException {
  ContentModerationException({
    required String message,
    int? statusCode,
    String? errorType,
    dynamic details,
  }) : super(
          message: message,
          statusCode: statusCode,
          errorType: errorType,
          code: 'CONTENT_MODERATION',
          details: details,
        );
}

class CacheException extends AppException {
  CacheException({
    required String message,
    String? code,
    dynamic details,
  }) : super(
          message: message,
          code: code ?? 'CACHE_ERROR',
          details: details,
        );
}

class ConfigurationException extends AppException {
  ConfigurationException({
    required String message,
    String? code,
    dynamic details,
  }) : super(
          message: message,
          code: code ?? 'CONFIG_ERROR',
          details: details,
        );
}