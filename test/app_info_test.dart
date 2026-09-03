import 'dart:io';

import 'package:foldboard/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the About version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml has no version field');
    expect(
      AppInfo.appVersion,
      match!.group(1),
      reason: 'Update AppInfo.appVersion in lib/app_info.dart',
    );
  });
}
