import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_input_safety.dart';

void main() {
  test('email validation agrees before registration and profile update', () {
    expect(isValidAuthEmail('  CLIENT+tag@Example.COM '), isTrue);
    for (final value in [
      '',
      'a',
      'a@',
      'a@host',
      'a b@host.ru',
      'a@@host.ru',
    ]) {
      expect(isValidAuthEmail(value), isFalse, reason: value);
    }
    expect(
      normalizeAuthEmail('  CLIENT+tag@Example.COM '),
      'client+tag@example.com',
    );
  });

  test('verification countdown follows elapsed wall time after suspension', () {
    final expiry = DateTime.utc(2026, 11, 9, 12, 5);
    expect(
      verificationSecondsLeft(expiry, now: DateTime.utc(2026, 11, 9, 12)),
      300,
    );
    expect(
      verificationSecondsLeft(
        expiry,
        now: DateTime.utc(2026, 11, 9, 12, 4, 50),
      ),
      10,
    );
    expect(verificationSecondsLeft(expiry, now: expiry), 0);
    expect(
      verificationSecondsLeft(
        expiry,
        now: expiry.add(const Duration(minutes: 5)),
      ),
      0,
    );
  });

  test(
    'return destination keeps internal business query and rejects external/auth paths',
    () {
      final pending = PendingAuthDestination();
      pending.remember(Uri.parse('/invoices?invoiceId=2792&clientCode=2A-01'));
      pending.remember(Uri.parse('/splash'));
      pending.remember(Uri.parse('/login'));
      expect(pending.take(), '/invoices?invoiceId=2792&clientCode=2A-01');
      expect(pending.take(), isNull);
      for (final value in [
        'https://evil.test/invoices',
        '//evil.test/invoices',
        '/login?next=/invoices',
        '/register',
        '/forgot-password',
        '/unknown',
      ]) {
        pending.remember(Uri.parse(value));
        expect(pending.take(), isNull, reason: value);
      }
    },
  );
}
