import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/anonymous_session.dart';
import 'services/watchdenchi_api.dart';

// アプリの色と選択肢
const Color cream = Color(0xFFF5EFE5);
const Color paper = Color(0xFFFFFBF5);
const Color ink = Color(0xFF58473D);
const Color mutedInk = Color(0xFF8C786B);
const Color coral = Color(0xFFD86B64);
const Color paleCoral = Color(0xFFF7DEDA);
const Color shelfBack = Color(0xFFEDE0CD);
const Color shelfEdge = Color(0xFFCA9D72);
const Color shelfDark = Color(0xFFA77D5D);

const List<String> batteryTypes = [
  '単1形', '単2形', '単3形', '単4形', '単5形',
  '9V形', 'CR2032', 'CR2025', 'LR44', 'その他',
];
const List<String> batteryChemistries = [
  'アルカリ', 'マンガン', '充電池', 'リチウム', '不明',
];
const List<String> mainManufacturers = [
  'Panasonic', 'maxell', 'FUJITSU', 'TOSHIBA', 'Duracell', 'その他',
];

// アプリ起動
void main() => runApp(const BatteryApp());

class BatteryApp extends StatelessWidget {
  const BatteryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: 'WatchDenchi',
      debugShowCheckedModeBanner: false,
      theme: CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: coral,
        scaffoldBackgroundColor: cream,
      ),
      home: SplashPage(),
    );
  }
}

// 最初のローディング画面
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..forward();
    _prepareAndEnter();
  }

  Future<void> _prepareAndEnter() async {
    
    final introDuration = Future<void>.delayed(const Duration(milliseconds: 3000));
    try {
      await Future.wait<Object?>([
        LocalBatteryStore.readInventory(),
        LocalBatteryStore.readDevices(),
        // GoのAPIが未完成の間はデフォルトで無効。ローカル保存を守る。
        if (enableServerAnonymousAuth)
          WatchDenchiServerServices.auth.restoreOrCreate(),
      ]);
    } catch (error) {
      debugPrint('起動時のデータ確認に失敗: $error');
    }
    await introDuration;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      CupertinoPageRoute<void>(builder: (_) => const HomePage()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: cream,
      child: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final arrive = Curves.easeInOutCubic
                  .transform(_controller.value.clamp(0.0, 1.0).toDouble());
              final reveal = Curves.easeOutCubic.transform(
                ((_controller.value - 0.51) / 0.49).clamp(0.0, 1.0).toDouble(),
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 155,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(-115 * (1 - arrive), 0),
                          child: const SoftBattery(
                            manufacturer: 'maxell', size: 145,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Transform.translate(
                          offset: Offset(115 * (1 - arrive), 0),
                          child: const SoftBattery(
                            manufacturer: 'Panasonic', size: 145,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  Opacity(
                    opacity: reveal,
                    child: Transform.translate(
                      offset: Offset(0, 13 * (1 - reveal)),
                      child: const Text(
                        'WatchDenchi',
                        style: TextStyle(
                          color: ink,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  Opacity(
                    opacity: reveal,
                    
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}


// 電池と機器のデータ
class BatteryEntry {
  const BatteryEntry({
    required this.type,
    required this.manufacturer,
    required this.quantity,
    required this.location,
    required this.chemistry,
  });

  final String type;
  final String manufacturer;
  final int quantity;
  final String location;
  final String chemistry;

  Map<String, dynamic> toJson() => {
        'type': type,
        'manufacturer': manufacturer,
        'quantity': quantity,
        'location': location,
        'chemistry': chemistry,
      };

  factory BatteryEntry.fromJson(Map<String, dynamic> json) => BatteryEntry(
        type: json['type'] as String? ?? 'その他',
        manufacturer: json['manufacturer'] as String? ?? '不明',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        location: json['location'] as String? ?? '',
        chemistry: json['chemistry'] as String? ?? '不明',
      );
}

class DeviceUsage {
  const DeviceUsage({
    required this.deviceName,
    required this.type,
    required this.manufacturer,
    required this.quantity,
    required this.startedAt,
    this.iconKey,
    this.status = 'active',
    this.endedAt,
    this.manualReplacementAt,
  });

  final String deviceName;
  final String type;
  final String manufacturer;
  final int quantity;
  final DateTime startedAt;
  // その他表示するやつ
  final String? iconKey;
  // 使用終了後も記録を残す。旧データは使用中として読み込む。
  final String status;
  final DateTime? endedAt;
  // ユーザーが指定した交換目安日。実測残量やAI予測値ではない。
  // 予測APIができたら別フィールドで保持する。
  final DateTime? manualReplacementAt;

  DeviceUsage withManualReplacementAt(DateTime? target) => DeviceUsage(
        deviceName: deviceName,
        type: type,
        manufacturer: manufacturer,
        quantity: quantity,
        startedAt: startedAt,
        iconKey: iconKey,
        status: status,
        endedAt: endedAt,
        manualReplacementAt: target,
      );

  bool get isActive => status == 'active';

  DeviceUsage finish(DateTime endTime) => DeviceUsage(
        deviceName: deviceName,
        type: type,
        manufacturer: manufacturer,
        quantity: quantity,
        startedAt: startedAt,
        iconKey: iconKey,
        status: 'inactive',
        endedAt: endTime,
        manualReplacementAt: manualReplacementAt,
      );

  Map<String, dynamic> toJson() => {
        'deviceName': deviceName,
        'type': type,
        'manufacturer': manufacturer,
        'quantity': quantity,
        'startedAt': startedAt.toIso8601String(),
        'iconKey': iconKey,
        'status': status,
        'endedAt': endedAt?.toIso8601String(),
        'manualReplacementAt': manualReplacementAt?.toIso8601String(),
      };

  factory DeviceUsage.fromJson(Map<String, dynamic> json) => DeviceUsage(
        deviceName: json['deviceName'] as String? ?? '名前のない機器',
        type: json['type'] as String? ?? 'その他',
        manufacturer: json['manufacturer'] as String? ?? '不明',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ??
            DateTime.now(),
        iconKey: json['iconKey'] as String?,
        status: json['status'] as String? ?? 'active',
        endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
        manualReplacementAt:
            DateTime.tryParse(json['manualReplacementAt'] as String? ?? ''),
      );
}

// APIの☆1登録・一覧を安全に動作確認するための試験フラグ。
// 移動・使用・交換を更新するサーバーAPIができるまでは本番ではfalse。
// ローカルの在庫は消さず、試験モードではサーバー側のみ表示する。
const bool enableServerInventory = bool.fromEnvironment(
  'WATCHDENCHI_ENABLE_SERVER_INVENTORY',
  defaultValue: false,
);

// 同じ端末内で在庫と機器の使用履歴を別々に保存
class LocalBatteryStore {
  LocalBatteryStore._();

  static final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const String inventoryKey = 'battery_inventory_v2';
  static const String olderInventoryKey = 'battery_inventory_v1';
  static const String deviceKey = 'watchdenchi_device_usage_v1';
  static const String disposalKey = 'watchdenchi_disposal_schedule_v1';

  static Future<List<BatteryEntry>> readInventory() async {
    if (enableServerInventory) {
      await WatchDenchiServerServices.auth.restoreOrCreate();
      final remote = await WatchDenchiServerServices.api.getBatteries();
      // DBのchemistry列はまだ設計されていない。推測せず「不明」にする。
      return remote.where((battery) => battery.quantity > 0).map((battery) =>
        BatteryEntry(
          type: battery.type,
          manufacturer: battery.manufacturer,
          quantity: battery.quantity,
          location: battery.storageLocation,
          chemistry: battery.chemistry ?? '不明',
        ),
      ).toList(growable: false);
    }
    final saved = await _prefs.getString(inventoryKey) ??
        await _prefs.getString(olderInventoryKey);
    if (saved == null) return [];
    final decoded = jsonDecode(saved) as List<dynamic>;
    return decoded
        .map((value) =>
            BatteryEntry.fromJson(Map<String, dynamic>.from(value as Map)))
        .where((entry) => entry.quantity > 0)
        .toList();
  }

  static Future<void> saveInventory(List<BatteryEntry> entries) async {
    // サーバー在庫モードでローカルだけ書き換えると、本数が矛盾するため防ぐ。
    if (enableServerInventory) {
      throw StateError('サーバーへの在庫更新APIが未実装です');
    }
    await _prefs.setString(
      inventoryKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  static Future<List<DeviceUsage>> readDevices() async {
    final saved = await _prefs.getString(deviceKey);
    if (saved == null) return [];
    final decoded = jsonDecode(saved) as List<dynamic>;
    return decoded
        .map((value) =>
            DeviceUsage.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  static Future<void> saveDevices(List<DeviceUsage> usages) async {
    await _prefs.setString(
      deviceKey,
      jsonEncode(usages.map((usage) => usage.toJson()).toList()),
    );
  }

  static Future<Map<String, dynamic>> readDisposalSchedule() async {
    final saved = await _prefs.getString(disposalKey);
    if (saved == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(saved) as Map);
    } catch (error) {
      debugPrint('回収日の読み込みに失敗: $error');
      return {};
    }
  }

  static Future<void> saveDisposalSchedule(
    String municipality, Map<String, DateTime> dates,
  ) async {
    await _prefs.setString(disposalKey, jsonEncode({
      'municipality': municipality,
      'dates': dates.map(
        (key, value) => MapEntry(key, value.toIso8601String()),
      ),
    }));
  }
}

// 手入力の「交換目安日」と実際の電池残量は別の情報。
// 将来の予測結果と混同しないように、日付は独立した値として保存する。
String formatReplacementDate(DateTime value) =>
    '${value.year}年${value.month}月${value.day}日';

int daysUntilReplacement(DateTime target, DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  final due = DateTime(target.year, target.month, target.day);
  return due.difference(day).inDays;
}

// 日付の入力は任意。キャンセル時はnullを返して以前の設定を維持する。
Future<DateTime?> pickManualReplacementDate(
  BuildContext context, {
  DateTime? current,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final maxDate = DateTime(today.year + 5, today.month, today.day);
  DateTime chosen = current != null && !current.isBefore(today) &&
          !current.isAfter(maxDate)
      ? current
      : today.add(const Duration(days: 90));
  if (chosen.isAfter(maxDate)) chosen = maxDate;
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (popupContext) => Container(
      height: 335,
      color: paper,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: 55,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.of(popupContext).pop(),
                    child: const Text('キャンセル',
                        style: TextStyle(color: mutedInk)),
                  ),
                  const Text('交換目安日を選ぶ',
                      style: TextStyle(color: ink,
                          fontWeight: FontWeight.w700)),
                  CupertinoButton(
                    onPressed: () => Navigator.of(popupContext).pop(chosen),
                    child: const Text('決定',
                        style: TextStyle(color: coral,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: chosen,
                minimumDate: today,
                maximumDate: maxDate,
                onDateTimeChanged: (value) => chosen = value,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    ),
  );
}

// 交換「予定日」との距離を小さなバッジにする。残量%ではない。
class _ManualReplacementBadge extends StatelessWidget {
  const _ManualReplacementBadge({required this.target});
  final DateTime? target;

  @override
  Widget build(BuildContext context) {
    final days = target == null
        ? null
        : daysUntilReplacement(target!, DateTime.now());
    final Color fill;
    final String label;
    final int batteryLevel;
    if (days == null) {
      fill = const Color(0xFF9B958F);
      label = '未設定';
      batteryLevel = 0;
    } else if (days <= 0) {
      fill = const Color(0xFFD86B64);
      label = '交換';
      batteryLevel = 0;
    } else if (days <= 14) {
      fill = const Color(0xFFE6AD36);
      label = '注意';
      batteryLevel = 1;
    } else {
      fill = const Color(0xFF68A678);
      label = '安心';
      batteryLevel = 3;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: paper, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (days != null) ...[
            _TinyBattery(level: batteryLevel),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

class _TinyBattery extends StatelessWidget {
  const _TinyBattery({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 15,
            height: 9,
            padding: const EdgeInsets.all(1.6),
            decoration: BoxDecoration(
              border: Border.all(color: CupertinoColors.white, width: 1.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: level == 0 ? 0.13 : level / 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: CupertinoColors.white,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 2,
            height: 4,
            decoration: const BoxDecoration(
              color: CupertinoColors.white,
              borderRadius: BorderRadius.horizontal(right: Radius.circular(1)),
            ),
          ),
        ],
      );
}

// 電池のメーカー別カラー
Color batteryAccent(String manufacturer) {
  final name = manufacturer.trim().toLowerCase();
  if (name.contains('panasonic') || name.contains('パナソニック')) {
    return const Color(0xFF7FA9D7); // 青みのあるパステル
  }
  if (name.contains('maxell') || name.contains('マクセル')) {
    return const Color(0xFFE16F74); // 赤
  }
  if (name.contains('fujitsu') || name.contains('富士通')) {
    return const Color(0xFFD4B36B); // 金
  }
  if (name.contains('toshiba') || name.contains('東芝')) {
    return const Color(0xFF95B4A2); // 緑
  }
  if (name.contains('duracell') || name.contains('デュラセル')) {
    return const Color(0xFFC9936F); // 茶
  }
  return const Color(0xFFA8B7AB); // その他の共通デザイン
}

// 電池作成
class SoftBattery extends StatelessWidget {
  const SoftBattery({super.key, required this.manufacturer, this.size = 65});

  final String manufacturer;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$manufacturer の電池',
      child: SizedBox(
        width: size * 0.53,
        height: size,
        child: CustomPaint(
          painter: _SoftBatteryPainter(batteryAccent(manufacturer)),
        ),
      ),
    );
  }
}

// 電池イラストの描画
class _SoftBatteryPainter extends CustomPainter {
  const _SoftBatteryPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 76);
    final paint = Paint()..isAntiAlias = true;

    // 底と金属キャップ
    paint.color = const Color(0xFFAAA29C);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(3, 8, 34, 65),
          const Radius.circular(5)),
      paint,
    );
    paint.color = const Color(0xFFAFA6A1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(14, 1, 12, 10),
          const Radius.circular(2.5)),
      paint,
    );
    paint.color = const Color(0xFFC2BAB5);
    canvas.drawRect(const Rect.fromLTWH(15, 1, 6, 8), paint);

    // 白い電池本体と色付きの上部
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 9, 34, 62), const Radius.circular(4)));
    paint.color = const Color(0xFFFAF9F3);
    canvas.drawRect(const Rect.fromLTWH(3, 9, 34, 62), paint);
    paint.color = accent;
    canvas.drawRect(const Rect.fromLTWH(3, 10, 34, 29), paint);


    paint.color = const Color(0x16000000);
    canvas.drawRect(const Rect.fromLTWH(30, 10, 7, 61), paint);
    paint.color = const Color(0x16FFFFFF);
    canvas.drawRect(const Rect.fromLTWH(7, 10, 6, 61), paint);

    // ＋ と −
    paint.color = const Color(0xFFFCFAF6);
    canvas.drawRect(const Rect.fromLTWH(18, 16, 5, 16), paint);
    canvas.drawRect(const Rect.fromLTWH(12.5, 21.5, 16, 5), paint);
    paint.color = const Color(0xFF80716A);
    canvas.drawRect(const Rect.fromLTWH(14, 61, 12, 3.5), paint);
    canvas.restore();

    paint.color = const Color(0x559B908A);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      const Rect.fromLTWH(3, 9, 34, 62),
      const Radius.circular(4),
    ));
    canvas.drawRect(const Rect.fromLTWH(3, 9, 34, 2), paint);
    canvas.restore();
    paint.color = const Color(0xFFB3A8A2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(3, 69, 34, 4),
          const Radius.circular(2)),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SoftBatteryPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

// アイコン
class DeviceIconOption {
  const DeviceIconOption(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

const List<DeviceIconOption> deviceIconOptions = [
  DeviceIconOption('tv', 'テレビ', CupertinoIcons.tv),
  DeviceIconOption('clock', '時計', CupertinoIcons.clock),
  DeviceIconOption('aircon', 'エアコン', CupertinoIcons.snow),
  DeviceIconOption('light', 'ライト', CupertinoIcons.lightbulb),
  DeviceIconOption('game', 'ゲーム機', CupertinoIcons.gamecontroller),
  DeviceIconOption('computer', 'パソコン', CupertinoIcons.desktopcomputer),
  DeviceIconOption('camera', 'カメラ', CupertinoIcons.camera),
  DeviceIconOption('audio', 'オーディオ', CupertinoIcons.speaker_2),
  DeviceIconOption('remote', 'リモコン', CupertinoIcons.slider_horizontal_3),
  DeviceIconOption('house', '住まい', CupertinoIcons.house),
  DeviceIconOption('other', 'その他', CupertinoIcons.question_circle),
];

// アイコン
DeviceIconOption resolvedDeviceIcon(String? iconKey) {
  for (final option in deviceIconOptions) {
    if (option.key == iconKey) return option;
  }
  return deviceIconOptions.last;
}

// ホームから開く画面のアニメーション
PageRouteBuilder<T> softPageRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 480),
      reverseTransitionDuration: const Duration(milliseconds: 360),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final progress = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInOutCubic,
        );
        return FadeTransition(
          opacity: progress,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.055, 0.025),
              end: Offset.zero,
            ).animate(progress),
            child: child,
          ),
        );
      },
    );

// ホーム画面・使用中の電池
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<BatteryEntry> inventory = [];
  List<DeviceUsage> devices = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadHome();
  }

  Future<void> loadHome() async {
    try {
      final loadedInventory = await LocalBatteryStore.readInventory();
      final loadedDevices = await LocalBatteryStore.readDevices();
      if (!mounted) return;
      setState(() {
        inventory = loadedInventory;
        devices = loadedDevices;
        loading = false;
      });
    } catch (error) {
      debugPrint('ホームの読み込みに失敗: $error');
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  Future<void> openInventory() async {
    await Navigator.of(context).push<void>(
      softPageRoute<void>(const InventoryPage()),
    );
    if (!mounted) return;
    await loadHome();
  }

  Future<void> openDisposal() async {
    await Navigator.of(context).push<void>(
      softPageRoute<void>(const DisposalPage()),
    );
  }

  // 使用中のアイコンをタップしたときだけ操作を表示
  Future<void> openDeviceActions(DeviceUsage usage) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(usage.deviceName),
        message: Text(
          '${usage.type}・${usage.quantity}本・${usage.manufacturer}'
          '\n交換目安：${usage.manualReplacementAt == null ? '未設定' : formatReplacementDate(usage.manualReplacementAt!)}'
          '\n※ 手入力の予定日です（実際の残量ではありません）',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(popupContext).pop('date'),
            child: Text(usage.manualReplacementAt == null
                ? '交換目安日を設定する' : '交換目安日を変更する'),
          ),
          if (usage.manualReplacementAt != null)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(popupContext).pop('clear-date'),
              child: const Text('交換目安日を解除する'),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(popupContext).pop('replace'),
            child: const Text('電池を交換する'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(popupContext).pop('finish'),
            child: const Text('使用を終了する'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('キャンセル'),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'finish') {
      await finishUsage(usage);
    } else if (action == 'replace') {
      await chooseReplacement(usage);
    } else if (action == 'date') {
      await updateManualReplacementDate(usage);
    } else if (action == 'clear-date') {
      await updateManualReplacementDate(usage, clear: true);
    }
  }

  Future<void> updateManualReplacementDate(
    DeviceUsage usage, {bool clear = false}
  ) async {
    final DateTime? selected;
    if (clear) {
      selected = null;
    } else {
      selected = await pickManualReplacementDate(
        context, current: usage.manualReplacementAt,
      );
      if (selected == null) return; // キャンセルは既存値を維持
    }
    if (!mounted) return;
    final index = devices.indexOf(usage);
    if (index < 0 || !devices[index].isActive) return;
    final updated = [...devices];
    updated[index] = usage.withManualReplacementAt(selected);
    try {
      await LocalBatteryStore.saveDevices(updated);
      if (!mounted) return;
      setState(() => devices = updated);
    } catch (error) {
      if (!mounted) return;
      await showError(context, '交換目安日を保存できませんでした\n$error');
    }
  }

  // 新しい電池を在庫棚から選び、同じ機器の使用履歴を継続する
  Future<void> chooseReplacement(DeviceUsage usage) async {
    if (enableServerInventory) {
      await showError(context, '交換時の在庫更新APIがまだないため、サーバー接続テスト中は交換できません');
      return;
    }
    final choices = inventory
        .where((entry) => entry.type == usage.type)
        .toList();
    if (choices.isEmpty) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('交換できる電池がありません'),
          content: Text('在庫棚に${usage.type}を登録してから交換してね。'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final selected = await showCupertinoModalPopup<BatteryEntry>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: const Text('交換する電池を選ぶ'),
        message: Text('${usage.deviceName}には${usage.type}を${usage.quantity}本使用中。新しい電池を選んでね。'),
        actions: [
          for (final entry in choices)
            if (entry.quantity >= usage.quantity)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.of(popupContext).pop(entry),
                child: Text(
                  '${entry.manufacturer}・${entry.chemistry}　${entry.location}　'
                  '${entry.quantity}本',
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 13,
                  horizontal: 16,
                ),
                child: Text(
                  '${entry.manufacturer}・${entry.chemistry}　${entry.location}　'
                  '${entry.quantity}本（在庫不足）',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: mutedInk, fontSize: 14),
                ),
              ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('キャンセル'),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('電池を交換しますか？'),
        content: Text(
          '${usage.deviceName}の使用中の電池を終了し、'
          '${selected.manufacturer}の${selected.type}を${usage.quantity}本使い始めます。'
          '\n古い電池の履歴は残し、在庫には戻しません。'
          '\n新しい電池の交換目安日は未設定になります。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('戻る'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('交換する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final deviceIndex = devices.indexOf(usage);
    final stockIndex = inventory.indexOf(selected);
    if (deviceIndex < 0 || !devices[deviceIndex].isActive || stockIndex < 0 ||
        inventory[stockIndex].quantity < usage.quantity) {
      await loadHome();
      return;
    }
    final now = DateTime.now();
    final nextDevices = [...devices];
    nextDevices[deviceIndex] = usage.finish(now);
    nextDevices.add(DeviceUsage(
      deviceName: usage.deviceName,
      type: selected.type,
      manufacturer: selected.manufacturer,
      quantity: usage.quantity,
      startedAt: now,
      iconKey: usage.iconKey,
    ));
    final nextStock = [...inventory];
    final remainder = selected.quantity - usage.quantity;
    if (remainder == 0) {
      nextStock.removeAt(stockIndex);
    } else {
      nextStock[stockIndex] = BatteryEntry(
        type: selected.type,
        manufacturer: selected.manufacturer,
        quantity: remainder,
        location: selected.location,
        chemistry: selected.chemistry,
      );
    }
    try {
      // 端末内保存は2つのキーなので、失敗時は使用履歴を戻すよう試みる
      await LocalBatteryStore.saveDevices(nextDevices);
      try {
        await LocalBatteryStore.saveInventory(nextStock);
      } catch (_) {
        await LocalBatteryStore.saveDevices(devices);
        rethrow;
      }
      if (!mounted) return;
      setState(() {
        devices = nextDevices;
        inventory = nextStock;
      });
    } catch (error) {
      if (!mounted) return;
      await showError(context, '電池の交換を保存できませんでした\n$error');
      await loadHome();
    }
  }

  Future<void> finishUsage(DeviceUsage usage) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('使用を終了しますか？'),
        content: Text('${usage.deviceName}で使っている${usage.quantity}本を使用中一覧から外します\n使用履歴は残し、在庫には戻しません'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('使用終了'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final index = devices.indexOf(usage);
    if (index < 0 || !devices[index].isActive) return;
    final updated = [...devices];
    updated[index] = usage.finish(DateTime.now());
    try {
      await LocalBatteryStore.saveDevices(updated);
      if (!mounted) return;
      setState(() => devices = updated);
    } catch (error) {
      if (!mounted) return;
      await showError(context, '使用情報を保存できませんでした\n$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeDevices = devices.where((item) => item.isActive).toList();
    return CupertinoPageScaffold(
      backgroundColor: cream,
      child: SafeArea(
        child: loading
            ? const Center(child: CupertinoActivityIndicator())
            : CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // 在庫棚のショートカット
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 20,
                            runSpacing: 16,
                            children: [
                              _InventoryAppShortcut(onPressed: openInventory),
                              _DisposalAppShortcut(onPressed: openDisposal),
                            ],
                          ),
                        ),
                        const SizedBox(height: 36),
                        const Text(
                          '使用中の機器',
                          style: TextStyle(
                            color: ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 19),
                        if (activeDevices.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 27),
                            child: Column(
                              children: [
                                Icon(CupertinoIcons.house_alt,
                                    color: const Color(0xFFC09A7D), size: 32),
                                const SizedBox(height: 10),
                                const Text('使用している機器はありません',
                                    style: TextStyle(color: ink, fontSize: 14)),
                                const SizedBox(height: 5),
                                const Text('在庫棚から電池を選んで登録',
                                    style: TextStyle(
                                        color: mutedInk, fontSize: 12)),
                              ],
                            ),
                          )
                        else
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final columns = constraints.maxWidth < 300 ? 2 : 3;
                              const spacing = 12.0;
                              final tileWidth =
                                  (constraints.maxWidth - (columns - 1) * spacing) /
                                      columns;
                              return Wrap(
                                spacing: spacing,
                                runSpacing: 15,
                                children: [
                                  for (final usage in activeDevices)
                                    SizedBox(
                                      width: tileWidth,
                                      child: TweenAnimationBuilder<double>(
                                        key: ValueKey(
                                          'device-${usage.startedAt.toIso8601String()}-${usage.deviceName}',
                                        ),
                                        tween: Tween<double>(begin: 0, end: 1),
                                        duration:
                                            const Duration(milliseconds: 570),
                                        curve: Curves.easeOutCubic,
                                        builder: (context, value, child) =>
                                            Opacity(
                                          opacity: value,
                                          child: Transform.translate(
                                            offset: Offset(0, (1 - value) * 15),
                                            child: child,
                                          ),
                                        ),
                                        child: CupertinoButton(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8, horizontal: 0),
                                          onPressed: () =>
                                              openDeviceActions(usage),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                               // アイコンの絵柄はそのまま。右上に交換目安のバッジ。
                                               SizedBox(
                                                 width: 82,
                                                 height: 85,
                                                 child: Stack(
                                                   clipBehavior: Clip.none,
                                                   children: [
                                                     Positioned(
                                                       left: 1,
                                                       bottom: 0,
                                                       child: Container(
                                                         width: 80,
                                                         height: 80,
                                                         alignment: Alignment.center,
                                                         decoration: BoxDecoration(
                                                           color: paleCoral,
                                                           borderRadius:
                                                               BorderRadius.circular(25),
                                                           border: Border.all(
                                                             color: const Color(0xFFF0CCC5),
                                                           ),
                                                         ),
                                                         child: Icon(
                                                           resolvedDeviceIcon(usage.iconKey).icon,
                                                           color: coral,
                                                           size: 39,
                                                         ),
                                                       ),
                                                     ),
                                                     Positioned(
                                                       top: -7,
                                                       right: -8,
                                                       child: _ManualReplacementBadge(
                                                         target: usage.manualReplacementAt,
                                                       ),
                                                     ),
                                                   ],
                                                 ),
                                               ),
                                              const SizedBox(height: 9),
                                              Text(
                                                usage.deviceName,
                                                textAlign: TextAlign.center,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: ink,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        if (activeDevices.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Text(
                            '※ 色は設定した交換目安日による表示です。電池の残量ではありません。',
                            style: TextStyle(color: mutedInk, fontSize: 11),
                          ),
                        ],
                        const SizedBox(height: 25),
                      ]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ホームの在庫棚アイコン
class _InventoryAppShortcut extends StatelessWidget {
  const _InventoryAppShortcut({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 118,
            height: 118,
            decoration: BoxDecoration(
              color: const Color(0xFFF1E1D0),
              borderRadius: BorderRadius.circular(29),
              border: Border.all(color: const Color(0xFFE6D6C4)),
            ),
            child: const Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SoftBattery(manufacturer: 'maxell', size: 76),
                  SizedBox(width: 3),
                  SoftBattery(manufacturer: 'Panasonic', size: 76),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '在庫棚',
            style: TextStyle(
              color: ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ホームの捨て方アイコン
class _DisposalAppShortcut extends StatelessWidget {
  const _DisposalAppShortcut({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E9DD),
                borderRadius: BorderRadius.circular(29),
                border: Border.all(color: const Color(0xFFCEDCCB)),
              ),
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(CupertinoIcons.calendar,
                        color: Color(0xFF7A9581), size: 61),
                    Positioned(
                      right: 21,
                      bottom: 19,
                      child: Transform.rotate(
                        angle: 0.18,
                        child: const SoftBattery(
                            manufacturer: 'maxell', size: 49),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text('電池の捨て方', style: TextStyle(
                color: ink, fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

// 電池の捨て方・回収日
class DisposalPage extends StatefulWidget {
  const DisposalPage({super.key});

  @override
  State<DisposalPage> createState() => _DisposalPageState();
}

class _DisposalPageState extends State<DisposalPage> {
  final TextEditingController municipalityController = TextEditingController();
  final Map<String, DateTime> dates = {};
  String selectedType = 'dry';
  String registeredMunicipality = '';
  bool loading = true;
  bool saving = false;
  bool saved = false;
  String? error;

  static const List<Map<String, String>> categories = [
    {'key': 'dry', 'name': '乾電池'},
    {'key': 'coin', 'name': 'コイン形'},
    {'key': 'button', 'name': 'ボタン電池'},
    {'key': 'recharge', 'name': '充電式'},
  ];

  @override
  void initState() {
    super.initState();
    loadSchedule();
  }

  @override
  void dispose() {
    municipalityController.dispose();
    super.dispose();
  }

  Future<void> loadSchedule() async {
    try {
      final data = await LocalBatteryStore.readDisposalSchedule();
      if (!mounted) return;
      final savedDates = data['dates'];
      setState(() {
        registeredMunicipality = data['municipality'] as String? ?? '';
        municipalityController.text = registeredMunicipality;
        if (savedDates is Map) {
          for (final entry in savedDates.entries) {
            final date = DateTime.tryParse(entry.value.toString());
            if (date != null) dates[entry.key.toString()] = date;
          }
        }
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '回収日の読み込みに失敗しました';
        loading = false;
      });
    }
  }

  String dateLabel(DateTime date) {
    const weekdays = ['日', '月', '火', '水', '木', '金', '土'];
    return '${date.year}年${date.month}月${date.day}日'
        '（${weekdays[date.weekday % 7]}）';
  }

  int? daysUntil(DateTime? value) {
    if (value == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(value.year, value.month, value.day);
    return target.difference(today).inDays;
  }

  Future<void> chooseDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime chosen = dates[selectedType] ?? today.add(const Duration(days: 7));
    if (chosen.isBefore(today)) chosen = today;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (popupContext) => Container(
        height: 345,
        color: paper,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      onPressed: () {
                        setState(() {
                          dates[selectedType] = chosen;
                          saved = false;
                          error = null;
                        });
                        Navigator.of(popupContext).pop();
                      },
                      child: const Text('決定',
                          style: TextStyle(color: coral,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: chosen,
                  minimumDate: today,
                  maximumDate: DateTime(today.year + 3, today.month, today.day),
                  onDateTimeChanged: (value) => chosen = value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> saveSchedule() async {
    final municipality = municipalityController.text.trim();
    if (municipality.isEmpty) {
      setState(() => error = '自治体・地区を入力してね');
      return;
    }
    if (dates.isEmpty) {
      setState(() => error = '回収日を1つ登録してね');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await LocalBatteryStore.saveDisposalSchedule(municipality, dates);
      if (!mounted) return;
      setState(() {
        registeredMunicipality = municipality;
        saving = false;
        saved = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = '保存できませんでした。もう一度試してね';
      });
    }
  }

  Future<void> copyReference(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('URLをコピーしました'),
        content: const Text('ブラウザに貼り付けて開いてね'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String get guidance {
    switch (selectedType) {
      case 'dry':
        return '単1〜単5形など。＋極と−極をテープで絶縁して、自治体の分別方法を確認しよう。';
      case 'coin':
        return 'CR2032・CR2025など。金属部分をテープで絶縁し、自治体の案内を確認しよう。';
      case 'button':
        return 'LR44など。自治体回収がなければ、ボタン電池の回収協力店を確認しよう。';
      case 'recharge':
        return 'ニッケル水素・リチウムイオンなど。回収対象かを確認して、協力店や自治体の案内に従おう。膨張・破損したものは回収店へ持ち込む前に相談してね。';
      default:
        return '自治体の案内を確認しよう。';
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = dates[selectedType];
    final remaining = daysUntil(next);
    final cityHasChanged = municipalityController.text.trim() !=
        registeredMunicipality;
    return CupertinoPageScaffold(
      backgroundColor: cream,
      navigationBar: const CupertinoNavigationBar(
        backgroundColor: cream,
        border: null,
        middle: Text('電池の捨て方', style: TextStyle(color: ink)),
      ),
      child: SafeArea(
        child: loading
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(22, 25, 22, 45),
                children: [
                  const Text('いつ、どうやって捨てる？',
                      style: TextStyle(color: ink,
                          fontSize: 23, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text('電池の種類ごとに、捨て方と回収日を確認。',
                      style: TextStyle(color: mutedInk, fontSize: 13)),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: softCardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 58,
                              height: 68,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E9DD),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(CupertinoIcons.calendar,
                                  color: Color(0xFF7A9581), size: 34),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('登録した次の回収日',
                                      style: TextStyle(color: mutedInk,
                                          fontSize: 13)),
                                  const SizedBox(height: 5),
                                  Text(next == null
                                          ? 'まだ登録されていません'
                                          : dateLabel(next),
                                      style: const TextStyle(color: ink,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (remaining != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 9),
                            decoration: BoxDecoration(
                              color: paleCoral,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              remaining < 0
                                  ? 'この回収日は過ぎました。日付を更新してね'
                                  : remaining == 0
                                      ? '今日が回収予定日！'
                                      : '回収予定日まであと $remaining 日',
                              style: const TextStyle(color: ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  const _FieldTitle('電池の種類'),
                  SizedBox(
                    height: 49,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final category in categories)
                          Padding(
                            padding: const EdgeInsets.only(right: 9),
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              color: selectedType == category['key']
                                  ? coral : paper,
                              borderRadius: BorderRadius.circular(14),
                              onPressed: () => setState(() {
                                selectedType = category['key']!;
                                saved = false;
                              }),
                              child: Text(category['name']!,
                                  style: TextStyle(
                                      color: selectedType == category['key']
                                          ? CupertinoColors.white : ink,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(17),
                    decoration: softCardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('捨てるときのポイント',
                            style: TextStyle(color: ink, fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        Text(guidance,
                            style: const TextStyle(color: mutedInk,
                                height: 1.55, fontSize: 13)),
                        const SizedBox(height: 10),
                        const Text('※ 実際の分別・回収場所は自治体や回収店の案内を優先してね。',
                            style: TextStyle(color: mutedInk, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 23),
                  const _FieldTitle('自治体・収集地区'),
                  CupertinoTextField(
                    controller: municipalityController,
                    placeholder: '例：〇〇市・△△地区',
                    padding: const EdgeInsets.all(15),
                    decoration: inputDecoration(),
                    onChanged: (_) => setState(() {
                      saved = false;
                      error = null;
                      if (registeredMunicipality.isNotEmpty &&
                          municipalityController.text.trim() !=
                              registeredMunicipality) {
                        dates.clear();
                      }
                    }),
                  ),
                  if (cityHasChanged && registeredMunicipality.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    const Text('地区が変わったので回収日を再設定してね。',
                        style: TextStyle(color: mutedInk, fontSize: 11)),
                  ],
                  const SizedBox(height: 20),
                  const _FieldTitle('次の回収日を登録'),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 15),
                    color: paper,
                    borderRadius: BorderRadius.circular(14),
                    onPressed: chooseDate,
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.calendar,
                            color: coral, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(next == null
                              ? 'カレンダーから日付を選ぶ'
                              : dateLabel(next),
                              style: const TextStyle(
                                  color: ink, fontSize: 14)),
                        ),
                        const Icon(CupertinoIcons.chevron_right,
                            color: mutedInk, size: 15),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('自治体の公式カレンダーで確認した日付を入力してね。自動取得はまだありません。',
                      style: TextStyle(color: mutedInk, fontSize: 11)),
                  if (error != null) ...[
                    const SizedBox(height: 13),
                    Text(error!, style: const TextStyle(
                        color: coral, fontSize: 12)),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      onPressed: saving ? null : saveSchedule,
                      child: Text(saving ? '保存中…' : '回収日を保存する'),
                    ),
                  ),
                  if (saved) ...[
                    const SizedBox(height: 9),
                    const Center(child: Text('保存したよ！',
                        style: TextStyle(color: Color(0xFF6E9273),
                            fontSize: 13,
                            fontWeight: FontWeight.w700))),
                  ],
                  const SizedBox(height: 27),
                  const Text('公式の案内',
                      style: TextStyle(color: ink,
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 9),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    color: paper,
                    borderRadius: BorderRadius.circular(13),
                    onPressed: () => copyReference(
                        'https://www.baj.or.jp/reuse_and_recycle/recycle/disposal.html'),
                    child: const Row(
                      children: [
                        Expanded(child: Text('電池工業会・捨て方ナビ',
                            style: TextStyle(color: ink, fontSize: 13))),
                        Icon(CupertinoIcons.doc_on_doc,
                            color: mutedInk, size: 18),
                      ],
                    ),
                  ),
                  const SizedBox(height: 9),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    color: paper,
                    borderRadius: BorderRadius.circular(13),
                    onPressed: () => copyReference(
                        'https://www.jbrc.com/general/recycle_kensaku/'),
                    child: const Row(
                      children: [
                        Expanded(child: Text('JBRC・回収協力店を探す',
                            style: TextStyle(color: ink, fontSize: 13))),
                        Icon(CupertinoIcons.doc_on_doc,
                            color: mutedInk, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// 在庫棚画面・電池の追加と移動
class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<BatteryEntry> entries = [];
  List<DeviceUsage> devices = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadEntries();
  }

  Future<void> loadEntries() async {
    try {
      final stock = await LocalBatteryStore.readInventory();
      final used = await LocalBatteryStore.readDevices();
      if (!mounted) return;
      setState(() {
        entries = stock;
        devices = used;
        loading = false;
      });
    } catch (error) {
      debugPrint('在庫の読み込みに失敗: $error');
      if (!mounted) return;
      setState(() => loading = false);
      await showError(context, '在庫の読み込みに失敗\n$error');
    }
  }

  Future<void> openAddPage() async {
    final newEntry = await Navigator.of(context).push<BatteryEntry>(
      CupertinoPageRoute<BatteryEntry>(builder: (_) => const AddBatteryPage()),
    );
    if (!mounted || newEntry == null) return;

    if (enableServerInventory) {
      if (newEntry.location.trim().isEmpty) {
        await showError(context, 'サーバー保存には保管場所の入力が必要です');
        return;
      }
      try {
        await WatchDenchiServerServices.auth.restoreOrCreate();
        // POSTに成功した後だけGETし直す。タイムアウト時に自動再送しない。
        await WatchDenchiServerServices.api.registerBattery(
          BatteryCreateRequest(
            type: newEntry.type,
            manufacturer: newEntry.manufacturer,
            quantity: newEntry.quantity,
            storageLocation: newEntry.location,
          ),
        );
        final refreshed = await LocalBatteryStore.readInventory();
        if (!mounted) return;
        setState(() => entries = refreshed);
      } catch (error) {
        if (!mounted) return;
        await showError(context,
            'サーバー登録・更新確認に失敗しました。二重登録を避けるため、再登録前に在庫を確認してね。\n$error');
      }
      return;
    }

    final updated = [...entries];
    final i = updated.indexWhere((entry) =>
        entry.type == newEntry.type &&
        entry.manufacturer.toLowerCase() ==
            newEntry.manufacturer.toLowerCase() &&
        entry.location == newEntry.location &&
        entry.chemistry == newEntry.chemistry);
    if (i == -1) {
      updated.add(newEntry);
    } else {
      final old = updated[i];
      updated[i] = BatteryEntry(
        type: old.type,
        manufacturer: old.manufacturer,
        quantity: old.quantity + newEntry.quantity,
        location: old.location,
        chemistry: old.chemistry,
      );
    }
    try {
      await LocalBatteryStore.saveInventory(updated);
      if (!mounted) return;
      setState(() => entries = updated);
    } catch (error) {
      if (!mounted) return;
      await showError(context, '登録を保存できませんでした\n$error');
    }
  }

  Future<void> moveBattery(BatteryEntry entry) async {
    if (enableServerInventory) {
      await showError(context, '保管場所の移動APIがまだないため、サーバー接続テスト中は移動できません');
      return;
    }
    final request = await Navigator.of(context).push<MoveBatteryRequest>(
      CupertinoPageRoute<MoveBatteryRequest>(
        builder: (_) => MoveBatteryPage(entry: entry),
      ),
    );
    if (!mounted || request == null) return;

    final index = entries.indexOf(entry);
    if (index == -1 || request.quantity < 1 ||
        request.quantity > entry.quantity) return;

    final destination = request.destination.trim();
    if (destination.isEmpty || destination == entry.location.trim()) return;

    final updated = [...entries];
    final remaining = entry.quantity - request.quantity;
    if (remaining == 0) {
      updated.removeAt(index);
    } else {
      updated[index] = BatteryEntry(
        type: entry.type,
        manufacturer: entry.manufacturer,
        quantity: remaining,
        location: entry.location,
        chemistry: entry.chemistry,
      );
    }

    final matchingIndex = updated.indexWhere((item) =>
        item.type == entry.type &&
        item.manufacturer.toLowerCase() == entry.manufacturer.toLowerCase() &&
        item.chemistry == entry.chemistry &&
        item.location == destination);
    if (matchingIndex >= 0) {
      final old = updated[matchingIndex];
      updated[matchingIndex] = BatteryEntry(
        type: old.type,
        manufacturer: old.manufacturer,
        quantity: old.quantity + request.quantity,
        location: old.location,
        chemistry: old.chemistry,
      );
    } else {
      updated.add(BatteryEntry(
        type: entry.type,
        manufacturer: entry.manufacturer,
        quantity: request.quantity,
        location: destination,
        chemistry: entry.chemistry,
      ));
    }

    try {
      await LocalBatteryStore.saveInventory(updated);
      if (!mounted) return;
      setState(() => entries = updated);
    } catch (error) {
      if (!mounted) return;
      await showError(context, '保管場所を変更できませんでした\n$error');
    }
  }

  Future<void> useBattery(BatteryEntry entry) async {
    if (enableServerInventory) {
      await showError(context, '使用情報のAPIがまだないため、サーバー接続テスト中は電池を使用できません');
      return;
    }
    final request = await showCupertinoModalPopup<UseBatteryRequest>(
      context: context,
      builder: (_) => UseBatterySheet(entry: entry),
    );
    if (!mounted || request == null) return;

    final index = entries.indexOf(entry);
    if (index == -1 || request.quantity > entry.quantity) return;
    final updatedStock = [...entries];
    final remaining = entry.quantity - request.quantity;
    if (remaining == 0) {
      updatedStock.removeAt(index);
    } else {
      updatedStock[index] = BatteryEntry(
        type: entry.type,
        manufacturer: entry.manufacturer,
        quantity: remaining,
        location: entry.location,
        chemistry: entry.chemistry,
      );
    }

    final updatedDevices = [...devices,
      DeviceUsage(
        deviceName: request.deviceName,
        type: entry.type,
        manufacturer: entry.manufacturer,
        quantity: request.quantity,
        startedAt: DateTime.now(),
        iconKey: request.iconKey,
        manualReplacementAt: request.manualReplacementAt,
      ),
    ];

    try {
      await LocalBatteryStore.saveDevices(updatedDevices);
      await LocalBatteryStore.saveInventory(updatedStock);
      if (!mounted) return;
      setState(() {
        entries = updatedStock;
        devices = updatedDevices;
      });
    } catch (error) {
      if (!mounted) return;
      await showError(context,
          '保存に失敗しました。（ 端末保存のエラー ）\n$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupedTypes = <String>[
      ...batteryTypes.where((type) => entries.any((e) => e.type == type)),
      ...entries.map((e) => e.type).where((t) => !batteryTypes.contains(t)).toSet(),
    ];

    return CupertinoPageScaffold(
      backgroundColor: cream,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: cream,
        border: null,
        middle: const Text('在庫棚', style: TextStyle(color: ink)),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: openAddPage,
          child: const Icon(CupertinoIcons.add_circled_solid,
              size: 28, color: coral),
        ),
      ),
      child: SafeArea(
        child: loading
            ? const Center(child: CupertinoActivityIndicator())
            : entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SoftBattery(manufacturer: 'maxell', size: 95),
                          const SizedBox(height: 14),
                          const Text('在庫はありません',
                              style: TextStyle(
                                  color: ink, fontSize: 19,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          const Text('右上の＋から電池を追加',
                              style: TextStyle(color: mutedInk)),
                          const SizedBox(height: 18),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
                    children: [
                      const SizedBox(height: 18),
                      for (final type in groupedTypes)
                        TweenAnimationBuilder<double>(
                          key: ValueKey('shelf-$type'),
                          tween: Tween<double>(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) => Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, (1 - value) * 30),
                              child: child,
                            ),
                          ),
                          child: _ShelfSection(
                            title: type,
                            entries: entries.where((e) => e.type == type).toList(),
                            onUse: useBattery,
                            onMove: moveBattery,
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}

// 電池選択・棚の表示
class _ShelfSection extends StatelessWidget {
  const _ShelfSection({
    required this.title,
    required this.entries,
    required this.onUse,
    required this.onMove,
  });

  final String title;
  final List<BatteryEntry> entries;
  final ValueChanged<BatteryEntry> onUse;
  final ValueChanged<BatteryEntry> onMove;

  @override
  Widget build(BuildContext context) {
    final totalCount = entries.fold<int>(0, (sum, e) => sum + e.quantity);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        decoration: BoxDecoration(
          color: shelfBack,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE0CAAE), width: 2),
          boxShadow: const [
            BoxShadow(color: Color(0x11000000),
                blurRadius: 12, offset: Offset(0, 5)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 電池の種類と合計本数
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: paper,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(title, style: const TextStyle(
                      color: ink, fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 11),
                Text('計${totalCount}本', style: const TextStyle(
                    color: mutedInk, fontSize: 13,
                    fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            for (final entry in entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(5, 5, 5, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry.manufacturer,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: ink, fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 1),
                              Text([
                                if (entry.chemistry.isNotEmpty) entry.chemistry,
                                if (entry.location.isNotEmpty) entry.location,
                              ].join(' ・ '),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: mutedInk, fontSize: 12)),
                            ],
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          onPressed: () => onMove(entry),
                          child: const Icon(CupertinoIcons.ellipsis,
                              color: ink, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // 画面幅で電池の表示本数と棚板の幅を変える
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const batteryWidth = 46.0;
                        const gap = 4.0;
                        const badgeWidth = 43.0;
                        final maxWidth = constraints.maxWidth;

                        var fit = ((maxWidth + gap) /
                            (batteryWidth + gap)).floor();
                        if (fit < 1) fit = 1;
                        if (fit > 10) fit = 10;

                        var shown = entry.quantity < fit
                            ? entry.quantity : fit;
                        if (entry.quantity > shown) {
                          // ＋本数の表示場所を確保
                          var withBadge = ((maxWidth - badgeWidth) /
                              (batteryWidth + gap)).floor();
                          if (withBadge < 1) withBadge = 1;
                          if (withBadge > 10) withBadge = 10;
                          shown = entry.quantity < withBadge
                              ? entry.quantity : withBadge;
                        }
                        final extra = entry.quantity - shown;
                        final itemsWidth = shown * batteryWidth +
                            (shown > 0 ? (shown - 1) * gap : 0) +
                            (extra > 0 ? gap + badgeWidth : 0);
                        final shelfWidth = (itemsWidth + 8)
                            .clamp(0.0, maxWidth).toDouble();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (var i = 0; i < shown; i++) ...[
                                  if (i > 0) const SizedBox(width: gap),
                                  SizedBox(
                                    width: batteryWidth,
                                    child: _LiftBatteryOnTap(
                                      onTap: () => onUse(entry),
                                      child: Center(
                                        child: SoftBattery(
                                          manufacturer: entry.manufacturer,
                                          size: 70,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                if (extra > 0) ...[
                                  const SizedBox(width: gap),
                                  GestureDetector(
                                    onTap: () => onUse(entry),
                                    child: Container(
                                      width: badgeWidth,
                                      height: 37,
                                      margin: const EdgeInsets.only(bottom: 3),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: paper.withAlpha(195),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text('+$extra',
                                          style: const TextStyle(color: ink,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            // 電池の底と棚板を接地させる
                            Transform.translate(
                              offset: const Offset(0, -4),
                              child: Container(
                                width: shelfWidth,
                                height: 12,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Color(0xFFE2BD91), shelfEdge, shelfDark],
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0x23000000),
                                        blurRadius: 4, offset: Offset(0, 3)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
            ],
          ],
        ),
      ),
    );
  }
}

// 電池をタップした時のアニメーション
class _LiftBatteryOnTap extends StatefulWidget {
  const _LiftBatteryOnTap({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_LiftBatteryOnTap> createState() => _LiftBatteryOnTapState();
}

class _LiftBatteryOnTapState extends State<_LiftBatteryOnTap> {
  bool lifted = false;
  bool busy = false;

  Future<void> handleTap() async {
    if (busy) return;
    busy = true;
    setState(() => lifted = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => lifted = false);
    widget.onTap();
    busy = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: handleTap,
      child: AnimatedSlide(
        offset: lifted ? const Offset(0, -0.22) : Offset.zero,
        duration: const Duration(milliseconds: 290),
        curve: Curves.easeOutCubic,
        child: AnimatedScale(
          scale: lifted ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 290),
          curve: Curves.easeOutBack,
          child: widget.child,
        ),
      ),
    );
  }
}

// 保管場所変更のデータ
class MoveBatteryRequest {
  const MoveBatteryRequest({
    required this.destination,
    required this.quantity,
  });

  final String destination;
  final int quantity;
}

// 保管場所変更画面の背景シルエット
class _FaintBatterySilhouette extends StatelessWidget {
  const _FaintBatterySilhouette({
    required this.width,
    required this.height,
    required this.angle,
    required this.opacity,
  });

  final double width;
  final double height;
  final double angle;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: angle,
          child: CustomPaint(
            size: Size(width, height),
            painter: const _FaintBatteryPainter(),
          ),
        ),
      ),
    );
  }
}

class _FaintBatteryPainter extends CustomPainter {
  const _FaintBatteryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFAE8D74)
      ..isAntiAlias = true;
    final w = size.width;
    final h = size.height;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.36, h * 0.015, w * 0.28, h * 0.065),
        Radius.circular(w * 0.05),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.12, h * 0.08, w * 0.76, h * 0.86),
        Radius.circular(w * 0.14),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FaintBatteryPainter oldDelegate) => false;
}

// 保管場所変更画面の大きい電池シルエット
class _MoveBatterySilhouetteBackground extends StatelessWidget {
  const _MoveBatterySilhouetteBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return ClipRect(
            child: Stack(
              children: [
                Positioned(
                  right: -w * 0.025,
                  top: h * 0.23,
                  child: _FaintBatterySilhouette(
                    width: w * 0.42,
                    height: h * 0.49,
                    angle: 0.15,
                    opacity: 0.085,
                  ),
                ),
                Positioned(
                  left: -w * 0.10,
                  bottom: -h * 0.115,
                  child: _FaintBatterySilhouette(
                    width: w * 0.47,
                    height: h * 0.58,
                    angle: -0.20,
                    opacity: 0.075,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// 移動先のピンマーク
class _DestinationPinIcon extends StatelessWidget {
  const _DestinationPinIcon({this.size = 19});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: const CustomPaint(painter: _DestinationPinPainter()),
      );
}

class _DestinationPinPainter extends CustomPainter {
  const _DestinationPinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = coral
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final pin = Path()
      ..moveTo(12, 21.5)
      ..cubicTo(9.6, 19, 4, 14.7, 4, 10.5)
      ..cubicTo(4, 6.1, 7.6, 3, 12, 3)
      ..cubicTo(16.4, 3, 20, 6.1, 20, 10.5)
      ..cubicTo(20, 14.7, 14.4, 19, 12, 21.5);
    canvas.drawPath(pin, paint);
    canvas.drawCircle(const Offset(12, 10.4), 3, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DestinationPinPainter oldDelegate) => false;
}

// 保管場所変更画面
class MoveBatteryPage extends StatefulWidget {
  const MoveBatteryPage({super.key, required this.entry});

  final BatteryEntry entry;

  @override
  State<MoveBatteryPage> createState() => _MoveBatteryPageState();
}

class _MoveBatteryPageState extends State<MoveBatteryPage> {
  final TextEditingController locationController = TextEditingController();
  int count = 1;
  String? error;

  @override
  void dispose() {
    locationController.dispose();
    super.dispose();
  }

  void submit() {
    final destination = locationController.text.trim();
    if (destination.isEmpty) {
      setState(() => error = '移動先を入力してね');
      return;
    }
    if (destination == widget.entry.location.trim()) {
      setState(() => error = '現在とは違う場所を入力');
      return;
    }
    Navigator.of(context).pop(
      MoveBatteryRequest(destination: destination, quantity: count),
    );
  }

  @override
  Widget build(BuildContext context) {
    final oldLocation = widget.entry.location.isEmpty
        ? '未設定'
        : widget.entry.location;
    final destination = locationController.text.trim();
    final destinationLabel =
        destination.isEmpty ? '移動先を入力してください' : destination;
    final remaining = widget.entry.quantity - count;

    return CupertinoPageScaffold(
      backgroundColor: cream,
      navigationBar: const CupertinoNavigationBar(
        backgroundColor: cream,
        border: null,
        middle: Text('保管場所を変更', style: TextStyle(color: ink)),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 38),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: softCardDecoration(),
                  child: Row(
                    children: [
                      SoftBattery(
                        manufacturer: widget.entry.manufacturer,
                        size: 75,
                      ),
                      const SizedBox(width: 17),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.entry.manufacturer,
                                style: const TextStyle(color: ink, fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 5),
                            Text('${widget.entry.type}・${widget.entry.quantity}本',
                                style: const TextStyle(color: mutedInk,
                                    fontSize: 13)),
                            const SizedBox(height: 5),
                            Text('現在の保管場所：$oldLocation',
                                style: const TextStyle(color: mutedInk,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 27),
                const _FieldTitle('移動先の保管場所'),
                CupertinoTextField(
                  controller: locationController,
                  placeholder: '例：寝室の引き出し',
                  padding: const EdgeInsets.all(15),
                  decoration: inputDecoration(),
                  onChanged: (_) => setState(() => error = null),
                ),
                const SizedBox(height: 24),
                const _FieldTitle('移動する本数'),
                Row(
                  children: [
                    CupertinoButton(
                      color: const Color(0xFFE5D5C5),
                      padding: const EdgeInsets.all(10),
                      onPressed: count > 1
                          ? () => setState(() => count--)
                          : null,
                      child: const Icon(CupertinoIcons.minus,
                          color: ink, size: 20),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        child: Text('$count 本', key: ValueKey(count),
                            style: const TextStyle(color: ink, fontSize: 20,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    CupertinoButton(
                      color: const Color(0xFFE5D5C5),
                      padding: const EdgeInsets.all(10),
                      onPressed: count < widget.entry.quantity
                          ? () => setState(() => count++)
                          : null,
                      child: const Icon(CupertinoIcons.add,
                          color: ink, size: 20),
                    ),
                    const Spacer(),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      onPressed: () => setState(() => count = widget.entry.quantity),
                      child: const Text('全部',
                          style: TextStyle(color: coral, fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                  decoration: BoxDecoration(
                    color: paper.withAlpha(238),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: const Color(0xFFE7D8C6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('移動後のイメージ',
                          style: TextStyle(
                              color: ink, fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const SizedBox(
                            width: 24,
                            child: Center(
                              child: Icon(CupertinoIcons.house,
                                  color: mutedInk, size: 19),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(oldLocation,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: ink, fontSize: 13)),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Text('$remaining 本',
                                key: ValueKey('remaining-$remaining'),
                                style: const TextStyle(
                                    color: ink, fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          width: 24,
                          child: Center(
                            child: Icon(CupertinoIcons.arrow_down,
                                color: coral, size: 18),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          const SizedBox(
                            width: 24,
                            child: Center(child: _DestinationPinIcon(size: 19)),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(destinationLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: destination.isEmpty ? mutedInk : ink,
                                    fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Text('+$count 本',
                                key: ValueKey('moving-$count'),
                                style: const TextStyle(
                                    color: coral, fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Text(error!, style: const TextStyle(color: coral, fontSize: 13)),
                ],
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: submit,
                    child: const Text('この場所に移動する'),
                  ),
                ),
              ],
            ),
            const Positioned.fill(
              child: _MoveBatterySilhouetteBackground(),
            ),
          ],
        ),
      ),
    );
  }
}

// 電池使用の入力内容
class UseBatteryRequest {
  const UseBatteryRequest({
    required this.deviceName,
    required this.quantity,
    required this.iconKey,
    this.manualReplacementAt,
  });
  final String deviceName;
  final int quantity;
  final String iconKey;
  final DateTime? manualReplacementAt;
}

// 電池を使う機器の登録画面
class UseBatterySheet extends StatefulWidget {
  const UseBatterySheet({super.key, required this.entry});
  final BatteryEntry entry;

  @override
  State<UseBatterySheet> createState() => _UseBatterySheetState();
}

class _UseBatterySheetState extends State<UseBatterySheet> {
  final TextEditingController deviceController = TextEditingController();
  final FocusNode deviceFocus = FocusNode();
  List<DeviceUsage> previousDevices = [];
  int count = 1;
  String? iconKey; // 未選択
  String? error;
  String? historyHint;
  DateTime? manualReplacementAt;

  Future<void> chooseManualReplacementDate() async {
    final chosen = await pickManualReplacementDate(
      context, current: manualReplacementAt,
    );
    if (!mounted || chosen == null) return;
    setState(() => manualReplacementAt = chosen);
  }

  @override
  void initState() {
    super.initState();
    deviceFocus.addListener(_onFocusChanged);
    _loadPreviousDevices();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  // 使用終了後の履歴も含め、以前登録した機器を新しい順に並べる
  Future<void> _loadPreviousDevices() async {
    try {
      final usages = await LocalBatteryStore.readDevices();
      usages.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      if (!mounted) return;
      setState(() => previousDevices = usages);
    } catch (error) {
      debugPrint('最近使った機器を読み込めませんでした: $error');
      // 履歴が取得できなくても、従来の手入力で登録できる
    }
  }

  // 同名の機器は直近の使用情報だけを候補にする
  List<DeviceUsage> get recentSuggestions {
    final query = deviceController.text.trim().toLowerCase();
    final seen = <String>{};
    final results = <DeviceUsage>[];
    for (final usage in previousDevices) {
      final key = usage.deviceName.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      if (query.isNotEmpty && !key.contains(query)) continue;
      results.add(usage);
      if (results.length >= (query.isEmpty ? 5 : 8)) break;
    }
    return results;
  }

  // 候補を選ぶと、機器名・アイコン・前回使用本数を一括で入力
  void _selectPreviousDevice(DeviceUsage usage) {
    final stock = widget.entry.quantity;
    final chosenCount = usage.quantity > stock
        ? stock
        : (usage.quantity < 1 ? 1 : usage.quantity);
    deviceController.value = TextEditingValue(
      text: usage.deviceName,
      selection: TextSelection.collapsed(offset: usage.deviceName.length),
    );
    setState(() {
      iconKey = resolvedDeviceIcon(usage.iconKey).key;
      count = chosenCount;
      error = null;
      if (usage.type != widget.entry.type) {
        historyHint = '前回は${usage.type}を使用。今回は${widget.entry.type}を選択中だよ。電池の種類を確認してね。';
      } else if (usage.quantity > stock) {
        historyHint = '前回は${usage.quantity}本。今回は在庫に合わせて${stock}本にしたよ。';
      } else {
        historyHint = null;
      }
    });
    deviceFocus.unfocus();
  }

  Widget _buildRecentChip(DeviceUsage usage) {
    final selected = deviceController.text.trim() == usage.deviceName;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => _selectPreviousDevice(usage),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 230),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? paleCoral : paper,
          border: Border.all(
            color: selected ? coral : const Color(0xFFE6D9C8),
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(resolvedDeviceIcon(usage.iconKey).icon,
                color: selected ? coral : mutedInk, size: 17),
            const SizedBox(width: 6),
            Text(usage.deviceName,
                style: const TextStyle(color: ink, fontSize: 12)),
            const SizedBox(width: 7),
            Text('${usage.quantity}本',
                style: const TextStyle(color: mutedInk, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    deviceFocus.removeListener(_onFocusChanged);
    deviceFocus.dispose();
    deviceController.dispose();
    super.dispose();
  }

  void submit() {
    final name = deviceController.text.trim();
    if (name.isEmpty) {
      setState(() => error = '使う機器の名前を入力');
      return;
    }
    if (iconKey == null) {
      setState(() => error = '機器のアイコンを選んでね');
      return;
    }
    Navigator.of(context).pop(
      UseBatteryRequest(
        deviceName: name,
        quantity: count,
        iconKey: iconKey!,
        manualReplacementAt: manualReplacementAt,
      ),
    );
  }

  Widget buildIconChoice({
    required String label,
    required IconData icon,
    required String choiceKey,
  }) {
    final selected = iconKey == choiceKey;
    return GestureDetector(
      onTap: () => setState(() {
        iconKey = choiceKey;
        error = null;
      }),
      child: AnimatedScale(
        scale: selected ? 1.08 : 0.96,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          width: 82,
          margin: const EdgeInsets.only(right: 9),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? paleCoral : paper,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? coral : const Color(0xFFE6D9C8),
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: selected ? coral : mutedInk, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? ink : mutedInk,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          22, 22, 22, MediaQuery.of(context).viewInsets.bottom + 26),
      decoration: const BoxDecoration(
        color: cream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 5),
              Text('${widget.entry.manufacturer}・${widget.entry.type}',
                  style: const TextStyle(color: mutedInk, fontSize: 14)),
              const SizedBox(height: 18),
              const Text('使う機器', style: TextStyle(
                  color: ink, fontWeight: FontWeight.w600)),
              const SizedBox(height: 7),
              CupertinoTextField(
                controller: deviceController,
                focusNode: deviceFocus,
                placeholder: '例：テレビのリモコン、壁掛け時計',
                padding: const EdgeInsets.all(15),
                decoration: inputDecoration(),
                onChanged: (_) => setState(() {
                  historyHint = null;
                  error = null;
                }),
              ),
              if (previousDevices.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      deviceController.text.trim().isEmpty
                          ? '最近使った機器'
                          : '名前に合う機器',
                      style: const TextStyle(
                        color: mutedInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const Text('タップで自動入力',
                        style: TextStyle(color: mutedInk, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 8),
                if (recentSuggestions.isNotEmpty)
                  SizedBox(
                    height: 43,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.zero,
                      itemCount: recentSuggestions.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                      itemBuilder: (context, index) =>
                          _buildRecentChip(recentSuggestions[index]),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 7),
                    child: Text('一致する機器はまだないよ',
                        style: TextStyle(color: mutedInk, fontSize: 12)),
                  ),
              ],
              if (historyHint != null) ...[
                const SizedBox(height: 7),
                Text(historyHint!,
                    style: const TextStyle(color: coral, fontSize: 12)),
              ],
              const SizedBox(height: 18),
              const Text('機器のアイコン', style: TextStyle(
                  color: ink, fontWeight: FontWeight.w600)),
              const SizedBox(height: 9),
              SizedBox(
                height: 104,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  clipBehavior: Clip.none,
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final option in deviceIconOptions)
                      buildIconChoice(
                        label: option.label,
                        icon: option.icon,
                        choiceKey: option.key,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text('使う本数', style: TextStyle(
                  color: ink, fontWeight: FontWeight.w600)),
              const SizedBox(height: 9),
              Row(
                children: [
                  CupertinoButton(
                    color: const Color(0xFFE5D5C5),
                    padding: const EdgeInsets.all(10),
                    onPressed: count > 1 ? () => setState(() => count--) : null,
                    child: const Icon(CupertinoIcons.minus,
                        color: ink, size: 20),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 19),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 360),
                      switchInCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.32),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        '$count 本',
                        key: ValueKey(count),
                        style: const TextStyle(
                          color: ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  CupertinoButton(
                    color: const Color(0xFFE5D5C5),
                    padding: const EdgeInsets.all(10),
                    onPressed: count < widget.entry.quantity
                        ? () => setState(() => count++) : null,
                    child: const Icon(CupertinoIcons.add,
                        color: ink, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text('交換の目安日（任意）', style: TextStyle(
                  color: ink, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                color: paper,
                borderRadius: BorderRadius.circular(14),
                onPressed: chooseManualReplacementDate,
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.calendar, color: coral, size: 19),
                    const SizedBox(width: 9),
                    Expanded(child: Text(
                      manualReplacementAt == null
                          ? '設定せずに使う（後から設定できます）'
                          : formatReplacementDate(manualReplacementAt!),
                      style: const TextStyle(color: ink, fontSize: 13),
                    )),
                    const Icon(CupertinoIcons.chevron_right,
                        color: mutedInk, size: 14),
                  ],
                ),
              ),
              if (manualReplacementAt != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    onPressed: () => setState(() => manualReplacementAt = null),
                    child: const Text('設定を解除',
                        style: TextStyle(color: mutedInk, fontSize: 12)),
                  ),
                ),
              const Text('設定した日付から緑・黄・赤の表示を切り替えます。'
                  '電池の残量を測定する機能ではありません。',
                  style: TextStyle(color: mutedInk, fontSize: 11, height: 1.5)),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: coral, fontSize: 12)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: submit,
                  child: const Text('この機器で使う'),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('やめる',
                      style: TextStyle(color: mutedInk)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 電池追加画面
class AddBatteryPage extends StatefulWidget {
  const AddBatteryPage({super.key});

  @override
  State<AddBatteryPage> createState() => _AddBatteryPageState();
}

class _AddBatteryPageState extends State<AddBatteryPage> {
  final TextEditingController otherManufacturerController =
      TextEditingController();
  final TextEditingController quantityController =
      TextEditingController(text: '1');
  final TextEditingController locationController = TextEditingController();
  String manufacturer = 'Panasonic';
  String type = '単3形';
  String chemistry = 'アルカリ';

  @override
  void dispose() {
    otherManufacturerController.dispose();
    quantityController.dispose();
    locationController.dispose();
    super.dispose();
  }

  Future<String?> pickOption(String title, List<String> values) {
    return showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final value in values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(popupContext).pop(value),
              child: Text(value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('キャンセル'),
        ),
      ),
    );
  }

  Future<void> submit() async {
    final actualManufacturer = manufacturer == 'その他'
        ? otherManufacturerController.text.trim()
        : manufacturer;
    final quantity = int.tryParse(quantityController.text.trim());
    if (actualManufacturer.isEmpty) {
      await showError(context, 'メーカー名を入力');
      return;
    }
    if (quantity == null || quantity <= 0) {
      await showError(context, '本数は1以上の整数を入力');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(BatteryEntry(
      type: type,
      manufacturer: actualManufacturer,
      quantity: quantity,
      location: locationController.text.trim(),
      chemistry: chemistry,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: cream,
      navigationBar: const CupertinoNavigationBar(
        backgroundColor: cream,
        border: null,
        middle: Text('電池を追加', style: TextStyle(color: ink)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
          children: [
            const Center(child: SoftBattery(manufacturer: 'maxell', size: 88)),
            const SizedBox(height: 14),
            const _FieldTitle('メーカー'),
            _PickerField(
              value: manufacturer,
              onTap: () async {
                final selected = await pickOption('メーカー', mainManufacturers);
                if (!mounted || selected == null) return;
                setState(() => manufacturer = selected);
              },
            ),
            if (manufacturer == 'その他') ...[
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: otherManufacturerController,
                placeholder: 'メーカー名（例：三菱電機）',
                padding: const EdgeInsets.all(15),
                decoration: inputDecoration(),
              ),
              const SizedBox(height: 6),
              const Text('デザインは共通ですが、入力したメーカー名は保存します。',
                  style: TextStyle(color: mutedInk, fontSize: 11)),
            ],
            const SizedBox(height: 19),
            const _FieldTitle('電池のサイズ'),
            _PickerField(
              value: type,
              onTap: () async {
                final selected = await pickOption('電池のサイズ', batteryTypes);
                if (!mounted || selected == null) return;
                setState(() => type = selected);
              },
            ),
            const SizedBox(height: 19),
            const _FieldTitle('電池の中身'),
            _PickerField(
              value: chemistry,
              onTap: () async {
                final selected = await pickOption('電池の中身', batteryChemistries);
                if (!mounted || selected == null) return;
                setState(() => chemistry = selected);
              },
            ),
            const SizedBox(height: 19),
            const _FieldTitle('本数'),
            CupertinoTextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              placeholder: '例：4',
              padding: const EdgeInsets.all(15),
              decoration: inputDecoration(),
            ),
            const SizedBox(height: 19),
            const _FieldTitle('保管場所（任意）'),
            CupertinoTextField(
              controller: locationController,
              placeholder: '例：リビングの引き出し',
              padding: const EdgeInsets.all(15),
              decoration: inputDecoration(),
            ),
            const SizedBox(height: 27),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: submit,
                child: const Text('在庫棚に追加する'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 共通の入力パーツ
class _FieldTitle extends StatelessWidget {
  const _FieldTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: const TextStyle(
            color: ink, fontSize: 14, fontWeight: FontWeight.w600)),
      );
}

class _PickerField extends StatelessWidget {
  const _PickerField({required this.value, required this.onTap});
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        color: paper,
        borderRadius: BorderRadius.circular(14),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(value, style: const TextStyle(color: ink, fontSize: 15)),
            const Icon(CupertinoIcons.chevron_down,
                size: 15, color: mutedInk),
          ],
        ),
      );
}

// カード・入力欄のデザイン
BoxDecoration softCardDecoration() => BoxDecoration(
      color: paper,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(color: Color(0x0B573C25),
            blurRadius: 14, offset: Offset(0, 5)),
      ],
    );

BoxDecoration inputDecoration() => BoxDecoration(
      color: paper,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE6D9C8)),
    );

// エラー表示
Future<void> showError(BuildContext context, String message) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('確認してください'),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
