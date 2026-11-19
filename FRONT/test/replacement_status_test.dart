import 'package:battery_app/services/replacement_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime.utc(2026, 11, 19, 3);
  test('more than seven days before prediction', () {
    expect(replacementStatusFor('2026-11-27', now: today), '目安前');
  });
  test('seven days before prediction starts preparation', () {
    expect(replacementStatusFor('2026-11-26', now: today), '交換準備');
    expect(replacementStatusFor('2026-11-20', now: today), '交換準備');
  });
  test('prediction date and overdue dates show replacement guidance', () {
    expect(replacementStatusFor('2026-11-19', now: today), '交換目安');
    expect(replacementStatusFor('2026-11-18', now: today), '交換目安');
  });
  test('missing, malformed and nonexistent dates are not guessed', () {
    for (final date in [null, '', 'not-a-date', '2026-02-30', '2026-13-01']) {
      expect(replacementStatusFor(date, now: today), '予測なし');
    }
    expect(replacementStatusFor('2028-02-29', now: today), '目安前');
  });
  test('day boundary follows Japan time rather than UTC', () {
    expect(replacementStatusFor('2026-11-20',
      now: DateTime.utc(2026,11,19,14,59)), '交換準備');
    expect(replacementStatusFor('2026-11-20',
      now: DateTime.utc(2026,11,19,15)), '交換目安');
  });
}
