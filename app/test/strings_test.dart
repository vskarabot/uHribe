import 'package:flutter_test/flutter_test.dart';
import 'package:uhribe/l10n/strings.dart';

void main() {
  group('Strings.greeting', () {
    test('greets by first name only', () {
      expect(Strings.greeting('Joe'), 'Živijo, Joe!');
      expect(Strings.greeting('Joe Doe'), 'Živijo, Joe!');
    });

    test('falls back to a plain hello when there is no name', () {
      // Covers the profile still loading, a user who never set a display
      // name, and a name that is nothing but whitespace.
      expect(Strings.greeting(null), 'Živijo!');
      expect(Strings.greeting(''), 'Živijo!');
      expect(Strings.greeting('   '), 'Živijo!');
    });

    test('tolerates stray whitespace around and inside the name', () {
      expect(Strings.greeting('  Joe  '), 'Živijo, Joe!');
      expect(Strings.greeting('Joe   Doe'), 'Živijo, Joe!');
    });
  });

  group('Strings.peakCount', () {
    test('shows a bare total when nothing is filtered out', () {
      expect(Strings.peakCount(348, of: 348), '348');
      expect(Strings.peakCount(0, of: 0), '0');
    });

    test('shows shown-of-total the moment a filter narrows the list', () {
      expect(Strings.peakCount(12, of: 348), '12 / 348');
      // Filtered down to nothing still has to read as filtered, not empty.
      expect(Strings.peakCount(0, of: 348), '0 / 348');
    });
  });
}
