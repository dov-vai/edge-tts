import 'dart:core';

class TTSConfig {
  /// Represents the internal TTS configuration for Edge TTS's communicate class.

  String voice;
  String rate;
  String volume;
  String pitch;

  TTSConfig({
    required this.voice,
    required this.rate,
    required this.volume,
    required this.pitch,
  }) {
    // Validate parameters after initialization
    _postInit();
  }

  /// Validates the given string parameter based on type and pattern.
  ///
  /// Args:
  ///   - paramName: The name of the parameter.
  ///   - paramValue: The value of the parameter.
  ///   - pattern: The pattern to validate the parameter against.
  ///
  /// Returns:
  ///   - The validated parameter.

  static String validateStringParam({
    required String paramName,
    required String paramValue,
    required String pattern,
  }) {
    final regExp = RegExp(pattern);
    if (!regExp.hasMatch(paramValue)) {
      throw ArgumentError("Invalid $paramName '$paramValue'.");
    }
    return paramValue;
  }

  /// Validates the TTSConfig object after initialization.

  void _postInit() {
    final RegExp voicePattern = RegExp(r'^([a-z]{2,})-([A-Z]{2,})-(.+Neural)$');
    final match = voicePattern.firstMatch(voice);

    if (match != null) {
      var lang = match.group(1);
      var region = match.group(2);
      var name = match.group(3);

      if (name!.contains('-')) {
        region = '$region-${name.substring(0, name.indexOf('-'))}';
        name = name.substring(name.indexOf('-') + 1);
      }

      voice =
          'Microsoft Server Speech Text to Speech Voice ($lang-$region, $name)';
    }

    // Validate voice, rate, volume, and pitch
    validateStringParam(
      paramName: 'voice',
      paramValue: voice,
      pattern: r'^Microsoft Server Speech Text to Speech Voice \(.+,.+\)$',
    );
    validateStringParam(
      paramName: 'rate',
      paramValue: rate,
      pattern: r'^[+-]\d+%$',
    );
    validateStringParam(
      paramName: 'volume',
      paramValue: volume,
      pattern: r'^[+-]\d+%$',
    );
    validateStringParam(
      paramName: 'pitch',
      paramValue: pitch,
      pattern: r'^[+-]\d+Hz$',
    );
  }
}
