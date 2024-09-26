import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models.dart';

class CommUtils {
  CommUtils._();

  static (Map<String, Uint8List>, Uint8List) getHeadersAndData(
      Uint8List data, int headerLength) {
    final headers = <String, Uint8List>{};
    final headerData = data.sublist(0, headerLength);
    final lines = String.fromCharCodes(headerData).split('\r\n');

    for (var line in lines) {
      final parts = line.split(':');
      String key = parts[0];
      String value = parts.length > 1 ? parts.sublist(1).join(':') : '';
      headers[key] = Uint8List.fromList(value.trim().codeUnits);
    }

    final remainingData = data.sublist(headerLength + 2);
    return (headers, remainingData);
  }

  static String removeIncompatibleCharacters(String string) {
    // Removes unsupported characters (such as vertical tabs).
    var chars = string.split('');
    for (var i = 0; i < chars.length; i++) {
      var code = chars[i].codeUnitAt(0);
      if ((0 <= code && code <= 8) ||
          (11 <= code && code <= 12) ||
          (14 <= code && code <= 31)) {
        chars[i] = ' ';
      }
    }
    return chars.join('');
  }

  static String connectId() => const Uuid().v4().replaceAll('-', '');

  static Stream<String> splitTextByByteLength(
      String text, int byteLength) async* {
    var utf8Text = utf8.encode(text);
    while (utf8Text.length > byteLength) {
      // Find last space
      var splitAt = utf8Text.sublist(0, byteLength).lastIndexOf(32);

      splitAt = splitAt == -1 ? byteLength : splitAt;

      // Ensure proper handling of & symbols
      while (utf8Text.sublist(0, splitAt).contains(38)) {
        var ampersandIndex = utf8Text.sublist(0, splitAt).lastIndexOf(38);
        if (utf8Text.sublist(ampersandIndex, splitAt).contains(59)) {
          break;
        }
        splitAt = ampersandIndex - 1;

        if (splitAt == 0) {
          break;
        }
      }

      var chunk = utf8Text
          .sublist(0, splitAt)
          .map((e) => String.fromCharCode(e))
          .join();
      yield chunk;
      utf8Text = utf8Text.sublist(splitAt);
    }
    yield utf8Text.map((e) => String.fromCharCode(e)).join();
  }

  static String mkSSML(TTSConfig config, String escapedText) {
    return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
        "<voice name='${config.voice}'>"
        "<prosody pitch='${config.pitch}' rate='${config.rate}' volume='${config.volume}'>"
        "$escapedText"
        "</prosody>"
        "</voice>"
        "</speak>";
  }

  static String dateToString() {
    // Javascript-style date string.
    return HttpDate.format(DateTime.now().toUtc());
  }

  static String ssmlHeadersPlusData(
      String requestId, String timestamp, String ssml) {
    return "X-RequestId:$requestId\r\n"
        "Content-Type:application/ssml+xml\r\n"
        "X-Timestamp:${timestamp}Z\r\n"
        "Path:ssml\r\n\r\n"
        "$ssml";
  }

  static int calcMaxMsgSize(TTSConfig ttsConfig) {
    const int websocketMaxSize = 65536; // 2^16
    var overheadPerMessage =
        ssmlHeadersPlusData(connectId(), dateToString(), mkSSML(ttsConfig, ''))
                .length +
            50;
    return websocketMaxSize - overheadPerMessage;
  }

  static String xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
