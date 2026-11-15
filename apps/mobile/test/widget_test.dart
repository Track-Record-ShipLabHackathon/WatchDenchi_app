import 'package:battery_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('Home opens the inventory and exposes registration', (
    WidgetTester tester,
  ) async {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);

    await tester.pumpWidget(const BatteryApp());
    await tester.pumpAndSettle();

    expect(find.text('WatchDenchi'), findsOneWidget);
    expect(find.text('ストック：0 本'), findsOneWidget);

    await tester.tap(find.text('在庫棚'));
    await tester.pumpAndSettle();

    expect(find.text('わたしの在庫棚'), findsOneWidget);
    expect(find.text('電池を追加'), findsOneWidget);
  });
}
