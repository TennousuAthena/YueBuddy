import 'package:flutter_test/flutter_test.dart';
import 'package:yue_buddy/features/onboarding/name_reading.dart';

void main() {
  test('reads a simplified Chinese name into common Jyutping', () {
    final reading = readName('陈小明', const {
      '陈': 'can4',
      '小': 'siu2',
      '明': 'ming4',
    });

    expect(reading.jyutping, 'can4 siu2 ming4');
    expect(reading.speakText, '陈小明');
    expect(reading.hasUnknown, isFalse);
  });

  test('keeps characters that have no reading', () {
    final reading = readName('阿A', const {'阿': 'aa3'});
    expect(reading.jyutping, 'aa3 A');
    expect(reading.hasUnknown, isTrue);
  });
}
