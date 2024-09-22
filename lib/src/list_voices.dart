import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'constants.dart';

const Map<String, String> headers = {
  'Authority': 'speech.platform.bing.com',
  'Sec-CH-UA':
      '" Not;A Brand";v="99", "Microsoft Edge";v="91", "Chromium";v="91"',
  'Sec-CH-UA-Mobile': '?0',
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/91.0.4472.77 Safari/537.36 Edg/91.0.864.41',
  'Accept': '*/*',
  'Sec-Fetch-Site': 'none',
  'Sec-Fetch-Mode': 'cors',
  'Sec-Fetch-Dest': 'empty',
  'Accept-Encoding': 'gzip, deflate, br',
  'Accept-Language': 'en-US,en;q=0.9',
};

Future<List<dynamic>> listVoices({String? proxy}) async {
  final HttpClient client = HttpClient();
  if (proxy != null) {
    client.findProxy = (uri) => 'PROXY $proxy';
  }

  final http.Client httpClient = IOClient(client);
  final Uri uri = Uri.parse(voiceListUrl);

  final http.Response response = await httpClient.get(uri, headers: headers);

  if (response.statusCode == 200) {
    return json.decode(response.body);
  } else {
    throw Exception('Failed to load voices');
  }
}

class VoicesManager {
  List<Map<String, dynamic>> voices = [];
  bool calledCreate = false;

  VoicesManager();

  static Future<VoicesManager> create(
      {List<Map<String, dynamic>>? customVoices}) async {
    final VoicesManager manager = VoicesManager();
    manager.voices =
        customVoices ?? await listVoices() as List<Map<String, dynamic>>;
    manager.voices = manager.voices.map((voice) {
      return {
        ...voice,
        'Language': (voice['Locale'] as String).split('-')[0],
      };
    }).toList();
    manager.calledCreate = true;
    return manager;
  }

  List<Map<String, dynamic>> find(Map<String, dynamic> attributes) {
    if (!calledCreate) {
      throw Exception(
          'VoicesManager.find() called before VoicesManager.create()');
    }

    return voices.where((voice) {
      return attributes.entries
          .every((entry) => voice[entry.key] == entry.value);
    }).toList();
  }
}
