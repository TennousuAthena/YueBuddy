import 'dart:convert';

import 'package:flutter/services.dart';

import 'name_reading.dart';

class JyutpingDictionary {
  const JyutpingDictionary(this.readings);

  final Map<String, String> readings;

  static Future<JyutpingDictionary> loadAsset([
    AssetBundle? bundle,
    String asset = 'assets/jyutping/chars.json',
  ]) async {
    final raw = await (bundle ?? rootBundle).loadString(asset);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return JyutpingDictionary(
      decoded.map((key, value) => MapEntry(key, value as String)),
    );
  }

  NameReading read(String name) => readName(name, readings);
}
