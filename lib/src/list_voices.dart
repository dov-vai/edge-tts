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

Future<List<Voice>> listVoices({String? proxy}) async {
  final HttpClient client = HttpClient();
  if (proxy != null) {
    client.findProxy = (uri) => 'PROXY $proxy';
  }

  final http.Client httpClient = IOClient(client);
  final Uri uri = Uri.parse(voiceListUrl);

  final http.Response response = await httpClient.get(uri, headers: headers);

  if (response.statusCode == 200) {
    List<Voice> voices = [];
    List<dynamic> data = json.decode(response.body);
    for (var json in data) {
      voices.add(Voice.fromJson(json));
    }
    return voices;
  } else {
    throw Exception('Failed to load voices');
  }
}

class Voice {
  final String name;
  final String shortName;
  final String gender;
  final String locale;
  final String suggestedCodec;
  final String friendlyName;
  final String status;
  final ({
    List<String> contentCategories,
    List<String> voicePersonalities
  }) voiceTag;

  Voice(
      {required this.name,
      required this.shortName,
      required this.gender,
      required this.locale,
      required this.suggestedCodec,
      required this.friendlyName,
      required this.status,
      required this.voiceTag});

  factory Voice.fromJson(Map<String, dynamic> json) {
    return Voice(
        name: json['Name'],
        shortName: json['ShortName'],
        gender: json['Gender'],
        locale: json['Locale'],
        suggestedCodec: json['SuggestedCodec'],
        friendlyName: json['FriendlyName'],
        status: json['Status'],
        voiceTag: (
          contentCategories:
              json['VoiceTag']['ContentCategories'].cast<String>(),
          voicePersonalities:
              json['VoiceTag']['VoicePersonalities'].cast<String>()
        ));
  }
}

class VoicesManager {
  List<Voice> voices = [];
  bool calledCreate = false;

  VoicesManager();

  static Future<VoicesManager> create({List<Voice>? customVoices}) async {
    final VoicesManager manager = VoicesManager();
    manager.voices = customVoices ?? await listVoices();
    manager.calledCreate = true;
    return manager;
  }

  List<Voice> find({
    String? name,
    String? shortName,
    String? gender,
    String? locale,
    String? suggestedCodec,
    String? friendlyName,
    String? status,
    List<String>? contentCategories,
    List<String>? voicePersonalities,
  }) {
    if (!calledCreate) {
      throw Exception(
          'VoicesManager.find() called before VoicesManager.create()');
    }

    return voices.where((voice) {
      bool matches = true;

      if (name != null) {
        matches = matches && voice.name == name;
      }
      if (shortName != null) {
        matches = matches && voice.shortName == shortName;
      }
      if (gender != null) {
        matches = matches && voice.gender == gender;
      }
      if (locale != null) {
        if (locale.contains('-')) {
          matches = matches && voice.locale == locale;
        } else {
          matches = matches && voice.locale.split('-')[0] == locale;
        }
      }
      if (suggestedCodec != null) {
        matches = matches && voice.suggestedCodec == suggestedCodec;
      }
      if (friendlyName != null) {
        matches = matches && voice.friendlyName == friendlyName;
      }
      if (status != null) {
        matches = matches && voice.status == status;
      }
      if (contentCategories != null) {
        matches = matches &&
            voice.voiceTag.contentCategories.every((category) {
              return contentCategories.contains(category);
            });
      }
      if (voicePersonalities != null) {
        matches = matches &&
            voice.voiceTag.voicePersonalities.every((voice) {
              return voicePersonalities.contains(voice);
            });
      }

      return matches;
    }).toList();
  }
}
