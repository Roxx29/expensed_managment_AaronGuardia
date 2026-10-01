import 'package:expense_manager/domain/security/pin_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hasher = PinHasher(iterations: 1000);

  test('hash/verify round-trip; wrong PIN fails', () async {
    final record = await hasher.hash('123456');
    expect(record, startsWith(r'pbkdf2-sha256$1000$'));
    expect(record.split(r'$'), hasLength(4));
    expect(await hasher.verify('123456', record), isTrue);
    expect(await hasher.verify('123457', record), isFalse);
    expect(await hasher.verify('', record), isFalse);
  });

  test('random salt: same PIN gives different records', () async {
    expect(await hasher.hash('1234'), isNot(await hasher.hash('1234')));
  });

  test('verify uses the iteration count stored in the record', () async {
    final record = await const PinHasher(iterations: 500).hash('9876');
    expect(await hasher.verify('9876', record), isTrue);
  });

  test('malformed records never verify', () async {
    for (final r in ['', 'x', r'pbkdf2-sha256$0$AA==$AA==', r'md5$1000$AA==$AA==', r'pbkdf2-sha256$1000$!!$AA==']) {
      expect(await hasher.verify('1234', r), isFalse, reason: r);
    }
  });

  test('PIN rules: 4–12 digits', () {
    expect(isValidPin('1234'), isTrue);
    expect(isValidPin('123456789012'), isTrue);
    expect(isValidPin('123'), isFalse);
    expect(isValidPin('1234567890123'), isFalse);
    expect(isValidPin('12a4'), isFalse);
    expect(isValidPin('12 34'), isFalse);
  });

  test('lockout: free attempts, then 30 s doubling, capped at 1 h', () {
    expect(lockoutFor(0), Duration.zero);
    expect(lockoutFor(4), Duration.zero);
    expect(lockoutFor(5), const Duration(seconds: 30));
    expect(lockoutFor(6), const Duration(minutes: 1));
    expect(lockoutFor(7), const Duration(minutes: 2));
    expect(lockoutFor(11), const Duration(seconds: 1920));
    expect(lockoutFor(12), const Duration(hours: 1));
    expect(lockoutFor(1000), const Duration(hours: 1));
  });
}
