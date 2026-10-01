/// Picks a Cantonese / Hong Kong Chinese locale from a device language list.
///
/// Matches zh-HK, yue-HK and close variants. Does not fall back to Mandarin
/// locales such as zh-CN or zh-TW.
String? pickCantoneseLocale(Iterable<Object?> languages) {
  final raw = languages.map((item) => item.toString()).toList();
  if (raw.isEmpty) return null;

  final normalized = raw
      .map((item) => item.replaceAll('_', '-').toLowerCase())
      .toList(growable: false);

  const exact = <String>[
    'zh-hk',
    'yue-hk',
    'zh-hant-hk',
    'yue-hant-hk',
    'zh-yue-hk',
    'yue',
    'zh-yue',
  ];

  for (final candidate in exact) {
    for (var i = 0; i < normalized.length; i++) {
      final value = normalized[i];
      if (value == candidate || value.startsWith('$candidate-')) {
        return raw[i];
      }
    }
  }

  for (var i = 0; i < normalized.length; i++) {
    final value = normalized[i];
    final isHongKong = value.contains('-hk') || value.endsWith('hk');
    final isCantoneseFamily =
        value.contains('yue') ||
        value.contains('zh-hant') ||
        value.startsWith('zh-');
    if (isHongKong && isCantoneseFamily && !value.contains('cn')) {
      return raw[i];
    }
  }

  return null;
}

const String cantoneseUnavailableMessage =
    '这台设备没有粤语语音。请在系统设置中下载「中文（香港）」语音后再试，本版不会用普通话代替朗读。';
