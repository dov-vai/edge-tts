import 'package:flutter_test/flutter_test.dart';

import 'package:edge_tts/edge_tts.dart';

void main() {
  test('listVoices doesn\'t throw exception', () async {
    expect (listVoices(), completes);
  });

  test('audio saved without exceptions', () async {
    var communicate = Communicate(text: "hello", voice: "en-US-AvaNeural");
    expect(communicate.save("hey.mp3"), completes);
  });
}
