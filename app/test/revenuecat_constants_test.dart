import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/core/constants/revenuecat_constants.dart';

void main() {
  group('RevenueCatConstants.isPlaceholderKey', () {
    test('detects the Android scaffold placeholder', () {
      expect(
        RevenueCatConstants.isPlaceholderKey(
            'goog_REPLACE_WITH_ANDROID_PUBLIC_KEY'),
        isTrue,
      );
    });

    test('accepts real-looking public SDK keys', () {
      expect(
        RevenueCatConstants.isPlaceholderKey('appl_OvhNypnojnQSEebpQtBikJYTHBa'),
        isFalse,
      );
      expect(
        RevenueCatConstants.isPlaceholderKey('goog_AbCdEfGhIjKlMnOpQrStUvWxYz'),
        isFalse,
      );
    });
  });
}
