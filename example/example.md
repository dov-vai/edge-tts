# Saving audio to file
```dart
import 'package:edge_tts/edge_tts.dart' as edge_tts;
// ...
var comm = edge_tts.Communicate(text:"hey hey hey");
comm.save("hey.mp3");
```

# Saving audio and its subtitles
```dart
// ...
var comm = edge_tts.Communicate(text:"hey hey hey");
comm.save("hey.mp3", metadataFileName: "subtitles.json");
```

# Streaming audio
```dart
// ...
var audio = File('audio.mp3').openSync(mode: FileMode.write);
await for (var message in communicate.stream()) {
    if (message['type'] == 'audio') {
      audio.add(message['data']);
    }
}
```

# Streaming subtitles
```dart
/// ...
RandomAccessFile metadata = File('metadata.json').openSync(mode: FileMode.write);
await for (var message in communicate.stream()) {
    if (message['type'] == 'WordBoundary') {
      metadata.writeStringSync('${json.encode(message)}\n');
    }
}
```

# Dynamic voice selection
```dart
/// ...
var manager = await edge_tts.VoicesManager.create();
var voices = manager.find(gender: "Male", locale: "es");

var comm = edge_tts.Communicate("hey hey hey", voices[0].name);
await comm.save("hey.mp3");
```

# More examples
More examples can be found in original Python project, this package should mimic its behavior, so it should be fairly simple to apply them here too:
https://github.com/rany2/edge-tts/tree/master/examples