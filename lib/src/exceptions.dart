/// Raised when an unknown response is received from the server.
class UnknownResponse implements Exception {
  final String message;

  UnknownResponse(
      [this.message = "An unknown response was received from the server."]);

  @override
  String toString() => "UnknownResponse: $message";
}

/// Raised when an unexpected response is received from the server.
/// This hasn't happened yet, but it's possible that the server will change its response format in the future.
class UnexpectedResponse implements Exception {
  final String message;

  UnexpectedResponse(
      [this.message = "An unexpected response was received from the server."]);

  @override
  String toString() => "UnexpectedResponse: $message";
}

/// Raised when no audio is received from the server.
class NoAudioReceived implements Exception {
  final String message;

  NoAudioReceived([this.message = "No audio was received from the server."]);

  @override
  String toString() => "NoAudioReceived: $message";
}

/// Raised when a WebSocket error occurs.
class WebSocketError implements Exception {
  final String message;

  WebSocketError([this.message = "A WebSocket error occurred."]);

  @override
  String toString() => "WebSocketError: $message";
}
