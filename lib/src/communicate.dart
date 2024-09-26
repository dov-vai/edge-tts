import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:edge_tts/src/utils/comm_utils.dart';

import 'constants.dart';
import 'exceptions.dart';
import 'models.dart';

class CommState {
  String partialText;
  int offsetCompensation;
  int lastDurationOffset;
  bool streamWasCalled;

  CommState(this.partialText, this.offsetCompensation, this.lastDurationOffset,
      this.streamWasCalled);
}

class Communicate {
  late TTSConfig ttsConfig;
  late Stream<String> texts;
  late CommState state;
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
    texts = CommUtils.splitTextByByteLength(
        CommUtils.xmlEscape(CommUtils.removeIncompatibleCharacters(text)),
        CommUtils.calcMaxMsgSize(ttsConfig));

    state = CommState("", 0, 0, false);
  }

  Map<String, dynamic> _parseMetadata(Uint8List data) {
    final decodedData = utf8.decode(data);
    final jsonData = jsonDecode(decodedData);

    for (var metaObj in jsonData['Metadata']) {
      final metaType = metaObj['Type'];

      if (metaType == 'WordBoundary') {
        final currentOffset =
            metaObj['Data']['Offset'] + state.offsetCompensation;
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
    socket.add("X-Timestamp:${CommUtils.dateToString()}\r\n"
        "Content-Type:application/json; charset=utf-8\r\n"
        "Path:speech.config\r\n\r\n"
        '{"context":{"synthesis":{"audio":{"metadataoptions":{'
        '"sentenceBoundaryEnabled":false,"wordBoundaryEnabled":true},'
        '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"'
        "}}}}\r\n");
  }

  void _sendSSMLRequest(WebSocket socket) {
    socket.add(CommUtils.ssmlHeadersPlusData(
        CommUtils.connectId(),
        CommUtils.dateToString(),
        CommUtils.mkSSML(ttsConfig, state.partialText)));
  }

  Stream<Map<String, dynamic>> _stream() async* {
    final uri = Uri.parse('$wssUrl&ConnectionId=${CommUtils.connectId()}');
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
        final parametersAndData = CommUtils.getHeadersAndData(
            encodedData, received.indexOf('\r\n\r\n'));

        final pathBinary = parametersAndData.$1['Path'];
        if (pathBinary == null) continue;
        final path = utf8.decode(pathBinary);

        if (path == 'audio.metadata') {
          final parsedMetadata = _parseMetadata(parametersAndData.$2);
          yield parsedMetadata;
          state.lastDurationOffset =
              parsedMetadata['offset'] + parsedMetadata['duration'];
        } else if (path == 'turn.end') {
          // Use average padding (8750000) typically added by the service
          // to the end of the audio data. This seems to work pretty
          // well for now, but we might ultimately need to use a
          // more sophisticated method like using ffmpeg to get
          // the actual duration of the audio data.
          state.offsetCompensation = state.lastDurationOffset + 8750000;
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
            CommUtils.getHeadersAndData(receivedBinary, headerLength);

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
    if (state.streamWasCalled) {
      throw Exception("stream can only be called once.");
    }
    state.streamWasCalled = true;

    await for (var text in texts) {
      state.partialText = text;
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
