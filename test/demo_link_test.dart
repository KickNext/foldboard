import 'package:foldboard/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only demo=1 requests the example project', () {
    expect(
      shouldOpenExample(Uri.parse('https://foldboard.app/?demo=1')),
      isTrue,
    );
    expect(shouldOpenExample(Uri.parse('https://foldboard.app/')), isFalse);
    expect(
      shouldOpenExample(Uri.parse('https://foldboard.app/?demo=0')),
      isFalse,
    );
  });
}
