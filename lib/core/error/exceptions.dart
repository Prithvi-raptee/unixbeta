// // lib/core/error/exceptions.dart
//
// class IpcException implements Exception {
//   final String message;
//   final dynamic originalException; // Optional: Store underlying error
//
//   IpcException(this.message, {this.originalException});
//
//   @override
//   String toString() => 'IpcException: $message ${originalException ?? ''}';
// }
//
// class IpcConnectionException extends IpcException {
//   IpcConnectionException(String message, {dynamic originalException})
//       : super(message, originalException: originalException);
// }
//
// class IpcParsingException extends IpcException {
//   IpcParsingException(String message, {dynamic originalException})
//       : super(message, originalException: originalException);
// }
//
// class IpcMasterException extends IpcException {
//   final int? masterStatusCode; // Store status code from master if available
//   IpcMasterException(String message, {this.masterStatusCode, dynamic originalException})
//       : super(message, originalException: originalException);
//
//   @override
//   String toString() => 'IpcMasterException: $message (Master Status: $masterStatusCode) ${originalException ?? ''}';
// }

class IpcException implements Exception {
  final String message;
  final dynamic originalException;
  IpcException(this.message, {this.originalException});

  @override
  String toString() {
    if (originalException != null) {
      return 'IpcException: $message (Original: $originalException)';
    }
    return 'IpcException: $message';
  }
}

// Specific exception types
class IpcConnectionException extends IpcException {
  IpcConnectionException(String message, {dynamic originalException})
      : super(message, originalException: originalException);
  @override String toString() => 'IpcConnectionException: $message ${originalException != null ? "(Original: $originalException)" : ""}';
}

class IpcParsingException extends IpcException {
  IpcParsingException(String message, {dynamic originalException})
      : super(message, originalException: originalException);
  @override String toString() => 'IpcParsingException: $message ${originalException != null ? "(Original: $originalException)" : ""}';
}

class IpcMasterException extends IpcException {
  final int? masterStatusCode;
  IpcMasterException(String message, {this.masterStatusCode, dynamic originalException})
      : super(message, originalException: originalException);
  @override String toString() => 'IpcMasterException: $message ${masterStatusCode != null ? "(Master Status: $masterStatusCode)" : ""} ${originalException != null ? "(Original: $originalException)" : ""}';
}

class IpcConfigurationException extends IpcException {
  IpcConfigurationException(String message, {dynamic originalException})
      : super(message, originalException: originalException);
  @override String toString() => 'IpcConfigurationException: $message ${originalException != null ? "(Original: $originalException)" : ""}';
}

