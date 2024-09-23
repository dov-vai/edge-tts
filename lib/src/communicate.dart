import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'constants.dart';
import 'exceptions.dart';
import 'models.dart';

(Map<String, Uint8List>, Uint8List) getHeadersAndData(
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

String removeIncompatibleCharacters(String string) {
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

String connectId() => const Uuid().v4().replaceAll('-', '');

Stream<String> splitTextByByteLength(String text, int byteLength) async* {
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

    var chunk =
        utf8Text.sublist(0, splitAt).map((e) => String.fromCharCode(e)).join();
    yield chunk;
    utf8Text = utf8Text.sublist(splitAt);
  }
  yield utf8Text.map((e) => String.fromCharCode(e)).join();
}

String mkSSML(TTSConfig config, String escapedText) {
  return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
      "<voice name='${config.voice}'>"
      "<prosody pitch='${config.pitch}' rate='${config.rate}' volume='${config.volume}'>"
      "$escapedText"
      "</prosody>"
      "</voice>"
      "</speak>";
}

String dateToString() {
  // Javascript-style date string.
  return HttpDate.format(DateTime.now().toUtc());
}

String ssmlHeadersPlusData(String requestId, String timestamp, String ssml) {
  return "X-RequestId:$requestId\r\n"
      "Content-Type:application/ssml+xml\r\n"
      "X-Timestamp:${timestamp}Z\r\n"
      "Path:ssml\r\n\r\n"
      "$ssml";
}

int calcMaxMsgSize(TTSConfig ttsConfig) {
  const int websocketMaxSize = 65536; // 2^16
  var overheadPerMessage =
      ssmlHeadersPlusData(connectId(), dateToString(), mkSSML(ttsConfig, '')).length + 50;
  return websocketMaxSize - overheadPerMessage;
}

String xmlEscape(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

class Communicate {
  late TTSConfig ttsConfig;
  late Stream<String> texts;
  late Map<String, dynamic> state;
  String? proxy;
  int connectTimeout;
  int receiveTimeout;

  Communicate(
      {required String text,
      String voice =
          'Microsoft Server Speech Text to Speech Voice (en-US, AriaNeural)',
      String rate = '+0%',
      String volume = '+0%',
      String pitch = '+0Hz',
      this.proxy,
      this.connectTimeout = 10,
      this.receiveTimeout = 60}) {
    ttsConfig =
        TTSConfig(voice: voice, rate: rate, volume: volume, pitch: pitch);
    texts = splitTextByByteLength(xmlEscape(removeIncompatibleCharacters(text)),
        calcMaxMsgSize(ttsConfig));

    state = {
      'partial_text': null,
      'offset_compensation': 0,
      'last_duration_offset': 0,
      'stream_was_called': false
    };
  }

  Map<String, dynamic> _parseMetadata(Uint8List data) {
    final decodedData = utf8.decode(data);
    final jsonData = jsonDecode(decodedData);

    for (var metaObj in jsonData['Metadata']) {
      final metaType = metaObj['Type'];

      if (metaType == 'WordBoundary') {
        final currentOffset =
            metaObj['Data']['Offset'] + state['offset_compensation'];
        final currentDuration = metaObj['Data']['Duration'];
        return {
          'type': metaType,
          'offset': currentOffset,
          'duration': currentDuration,
          'text': metaObj['Data']['text']['Text'],
        };
      }

      if (metaType != null || metaType == 'SessionEnd') {
        continue;
      }

      throw UnknownResponse('Unknown metadata type: $metaType');
    }

    throw UnexpectedResponse('No WordBoundary metadata found');
  }

  void _sendCommandRequest(WebSocket socket) {
    socket.add("X-Timestamp:${dateToString()}\r\n"
        "Content-Type:application/json; charset=utf-8\r\n"
        "Path:speech.config\r\n\r\n"
        '{"context":{"synthesis":{"audio":{"metadataoptions":{'
        '"sentenceBoundaryEnabled":false,"wordBoundaryEnabled":true},'
        '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"'
        "}}}}\r\n");
  }

  void _sendSSMLRequest(WebSocket socket) {
    socket.add(ssmlHeadersPlusData(
        connectId(), dateToString(), mkSSML(ttsConfig, state["partial_text"])));
  }

  Stream<Map<String, dynamic>> _stream() async* {
    final uri = Uri.parse('$wssUrl&ConnectionId=${connectId()}');
    final headers = {
      "Pragma": "no-cache",
      "Cache-Control": "no-cache",
      "Origin": "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold",
      "Accept-Encoding": "gzip, deflate, br",
      "Accept-Language": "en-US,en;q=0.9",
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
          " (KHTML, like Gecko) Chrome/91.0.4472.77 Safari/537.36 Edg/91.0.864.41",
    };
    final ws = await WebSocket.connect(uri.toString(), headers: headers);

    _sendCommandRequest(ws);
    _sendSSMLRequest(ws);

    // audioWasReceived indicates whether we have received audio data
    // from the websocket. This is so we can raise an exception if we
    // don't receive any audio data.
    bool audioWasReceived = false;

    await for (var received in ws) {
      if (received is String) {
        final encodedData = utf8.encode(received);
        final parametersAndData =
            getHeadersAndData(encodedData, received.indexOf('\r\n\r\n'));

        final pathBinary = parametersAndData.$1['Path'];
        if (pathBinary == null) continue;
        final path = utf8.decode(pathBinary);

        if (path == 'audio.metadata') {
          final parsedMetadata = _parseMetadata(parametersAndData.$2);
          yield parsedMetadata;
          state['last_duration_offset'] =
              parsedMetadata['offset'] + parsedMetadata['duration'];
        } else if (path == 'turn.end') {
          // Use average padding (8750000) typically added by the service
          // to the end of the audio data. This seems to work pretty
          // well for now, but we might ultimately need to use a
          // more sophisticated method like using ffmpeg to get
          // the actual duration of the audio data.
          state['offset_compensation'] =
              state['last_duration_offset'] + 8750000;
          break;
        } else if (!['response', 'turn.start'].contains(path)) {
          throw UnknownResponse('Unknown path received');
        }
      } else if (received is List<int>) {
        var receivedBinary = Uint8List.fromList(received);

        if (received.length < 2) {
          throw UnexpectedResponse('Binary message missing header length');
        }

        final headerLength =
            receivedBinary.sublist(0, 2).buffer.asByteData().getUint16(0);
        if (headerLength > received.length) {
          throw UnexpectedResponse('Header length greater than data length');
        }

        final parametersAndData =
            getHeadersAndData(receivedBinary, headerLength);

        final pathBinary = parametersAndData.$1['Path'];
        if (pathBinary == null) continue;
        final path = utf8.decode(pathBinary);
        if (path != 'audio') {
          throw UnexpectedResponse('Binary message path is not audio');
        }

        final contentTypeBinary = parametersAndData.$1['Content-Type'];
        if (contentTypeBinary == null) continue;
        final contentType = utf8.decode(contentTypeBinary);

        if (!['audio/mpeg', null].contains(contentType)) {
          throw UnexpectedResponse('Unexpected Content-Type in binary message');
        }

        if (parametersAndData.$2.isEmpty) {
          continue;
        }

        audioWasReceived = true;
        yield {'type': 'audio', 'data': parametersAndData.$2};
      }
    }
    await ws.close();

    if (!audioWasReceived) {
      throw NoAudioReceived(
          "No audio was received. Please verify that your parameters are correct.");
    }
  }

  Stream<Map<String, dynamic>> stream() async* {
    if (state["stream_was_called"]) {
      throw Exception("stream can only be called once.");
    }
    state["stream_was_called"] = true;

    await for (var text in texts) {
      state["partial_text"] = text;
      await for (var message in _stream()) {
        yield message;
      }
    }
  }

  Future<void> save(String audioFileName, {String? metadataFileName}) async {
    RandomAccessFile? metadata;

    if (metadataFileName != null) {
      metadata = File(metadataFileName).openSync(mode: FileMode.write);
    }

    var audio = File(audioFileName).openSync(mode: FileMode.write);

    try {
      await for (var message in stream()) {
        if (message['type'] == 'audio') {
          audio.writeFromSync(message['data']);
        } else if (metadata != null && message['type'] == 'WordBoundary') {
          metadata.writeStringSync('${json.encode(message)}\n');
        }
      }
    } finally {
      await audio.close();
      if (metadata != null) {
        await metadata.close();
      }
    }
  }
}
