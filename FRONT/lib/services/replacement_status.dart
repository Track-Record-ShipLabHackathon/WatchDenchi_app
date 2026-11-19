/// 交換推奨日（日本時間の暦日）から表示状態を決める。実測残量ではない。
String replacementStatusFor(String? date, {DateTime? now}) {
  if (date == null) return '予測なし';
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
  if (match == null) return '予測なし';
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final target = DateTime.utc(year, month, day);
  if (target.year != year || target.month != month || target.day != day) {
    return '予測なし';
  }
  final japanNow = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 9));
  final today = DateTime.utc(japanNow.year, japanNow.month, japanNow.day);
  final days = target.difference(today).inDays;
  if (days <= 0) return '交換目安';
  if (days <= 7) return '交換準備';
  return '目安前';
}
