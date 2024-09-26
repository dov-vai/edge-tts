<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

Microsoft Edge TTS (Read-Aloud). No API keys required.

Port of [edge-tts](https://github.com/rany2/edge-tts) project for Python. Thank you!

## Features

- Microsoft Edge Text-To-Speech
- Save audio, subtitles
- List, select voices

## Getting started

Simple example on how to save audio is below. More examples available in the examples section.

## Usage

```dart
import 'package:edge_tts/edge_tts.dart' as edge_tts;
// ...
var comm = edge_tts.Communicate(text:"hey hey hey");
comm.save("hey.mp3");
```