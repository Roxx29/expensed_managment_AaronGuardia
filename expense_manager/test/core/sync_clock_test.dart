import 'package:expense_manager/core/utils/sync_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(SyncClock.reset);

  test('an edit after seeing a newer change from another phone sorts after it', () {
    final otherPhone = DateTime.now().add(const Duration(minutes: 5)); // its clock runs ahead
    SyncClock.observe(otherPhone);
    expect(SyncClock.now().difference(otherPhone).inSeconds, greaterThanOrEqualTo(1));
  });

  test('without newer changes it is the phone clock', () {
    SyncClock.observe(DateTime(2000));
    expect(SyncClock.now().difference(DateTime.now()).inSeconds.abs(), lessThan(2));
  });

  test('a clock years ahead is ignored', () {
    SyncClock.observe(DateTime(3000));
    expect(SyncClock.now().year, lessThan(3000));
  });
}
