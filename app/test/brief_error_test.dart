import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/main.dart';

void main() {
  group('briefError', () {
    test('does NOT throw on a multi-line error with a SHORT first line (the bug)', () {
      // first line is 15 chars; the full string is well over 64 chars across
      // multiple lines. The old code did first.substring(0, 64) → RangeError.
      final e = StateError('keystore reset\n#0 TokenStorage.read\n#1 frame\n#2 frame frame frame frame');
      expect(e.toString().length, greaterThan(64));
      expect(e.toString().split('\n').first.length, lessThan(64));
      expect(() => briefError(e), returnsNormally);
      // Bound by the first line, never longer than 64.
      expect(briefError(e).length, lessThanOrEqualTo(64));
    });

    test('truncates a long single-line error to 64 chars', () {
      expect(briefError(Exception('x' * 200)).length, 64);
    });

    test('returns a short first line unchanged', () {
      expect(briefError(StateError('boom')), 'Bad state: boom');
    });

    test('prefers an AADSTS code when present (multi-line)', () {
      final e = Exception('AADSTS700082: refresh token expired due to inactivity\nstack...\nmore...');
      expect(briefError(e), 'AADSTS700082');
    });
  });
}
