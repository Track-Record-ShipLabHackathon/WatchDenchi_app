import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
    // 公開版でも毎回地域選択から始める。保存済み地域は候補欄に復元する。
    final introDuration = Future<void>.delayed(const Duration(milliseconds: 3000));
    try {
      await Future.wait<Object?>([
        LocalBatteryStore.readInventory(),
        LocalBatteryStore.readDevices(),
      ]);
    } catch (error) {
      debugPrint('起動時の保存データ確認に失敗: $error');
    }
    await introDuration;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      CupertinoPageRoute<void>(builder: (_) => const RegionSetupPage()),
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


// Go APIで試験する場合だけON。通常は既存のローカルUIと保存を維持する。
// 現行Go APIには「保管場所変更/使用開始/交換」がまだないため、
// 試験モードではこれらの操作を明示的に止め、DBとローカルの二重管理を避ける。
const bool enableServerInventory = bool.fromEnvironment(
  'WATCHDENCHI_ENABLE_SERVER_INVENTORY',
  defaultValue: false,
); // 通常公開版は端末内保存、api-previewビルドのみサーバー在庫

// 電池と機器のデータ
class BatteryEntry {
  const BatteryEntry({
    required this.type,
    required this.manufacturer,
    required this.quantity,
    required this.location,
    required this.chemistry,
    this.id,
  });

  // GoのBATTERY主キー。古いローカルデータにはないので任意。
  final int? id;
  final String type;
  final String manufacturer;
  final int quantity;
  final String location;
  final String chemistry;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'type': type,
        'manufacturer': manufacturer,
        'quantity': quantity,
        'location': location,
        'chemistry': chemistry,
      };

  factory BatteryEntry.fromJson(Map<String, dynamic> json) => BatteryEntry(
        id: (json['id'] as num?)?.toInt(),
        type: json['type'] as String? ?? 'その他',
        manufacturer: json['manufacturer'] as String? ?? '不明',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        location: json['location'] as String? ?? '',
        chemistry: json['chemistry'] as String? ?? '不明',
      );
}

// 発表用の画面確認: 実際の電池残量・Pythonの予測日ではない。
// 通常は「未設定」。?demoBadges=1 でサンプルの色分けを表示する。
// 状態はユーザーの手入力値。実測値やAI予測値ではない。
class _PresentationBatteryStatusBadge extends StatelessWidget {
  const _PresentationBatteryStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final fill = switch (status) {
      '安心' => const Color(0xFF68A678),
      '準備' => const Color(0xFFE6AD36),
      '交換' => const Color(0xFFD86B64),
      _ => const Color(0xFF9B958F),
    };
    final level = switch (status) {
      '安心' => 3,
      '準備' => 1,
      _ => 0,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: paper, width: 1.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (status != '未設定') ...[
          _PresentationTinyBattery(level: level),
          const SizedBox(width: 4),
        ],
        Text(status, style: const TextStyle(
          color: CupertinoColors.white, fontSize: 10,
          fontWeight: FontWeight.w700,
        )),
      ]),
    );
  }
}

class _PresentationTinyBattery extends StatelessWidget {
  const _PresentationTinyBattery({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 15, height: 9,
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
            width: 2, height: 4,
            decoration: const BoxDecoration(
              color: CupertinoColors.white,
              borderRadius: BorderRadius.horizontal(right: Radius.circular(1)),
            ),
          ),
        ],
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
    this.batteryStatus = '未設定',
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
  // 旧ローカルデータの読み込み互換性のためだけに保持する。
  // 手入力の日付は表示しない。将来のPython予測日とは別項目。
  final DateTime? manualReplacementAt;
  final String batteryStatus;

  DeviceUsage withBatteryStatus(String value) => DeviceUsage(
    deviceName: deviceName, type: type, manufacturer: manufacturer,
    quantity: quantity, startedAt: startedAt, iconKey: iconKey,
    status: status, endedAt: endedAt,
    manualReplacementAt: manualReplacementAt, batteryStatus: value,
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
        batteryStatus: batteryStatus,
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
        'batteryStatus': batteryStatus,
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
        batteryStatus: const ['安心', '準備', '交換', '未設定']
                .contains(json['batteryStatus'])
            ? json['batteryStatus'] as String
            : '未設定',
      );
}

// 同じ端末内で在庫と機器の使用履歴を別々に保存
class LocalBatteryStore {
  LocalBatteryStore._();

  static final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const String inventoryKey = 'battery_inventory_v2';
  static const String olderInventoryKey = 'battery_inventory_v1';
  static const String deviceKey = 'watchdenchi_device_usage_v1';
  static const String disposalKey = 'watchdenchi_disposal_schedule_v1';
  static const String regionSetupSeenKey = 'watchdenchi_region_setup_seen_v1';

  static Future<bool> hasSeenRegionSetup() async =>
      await _prefs.getBool(regionSetupSeenKey) ?? false;

  static Future<void> markRegionSetupSeen() async =>
      _prefs.setBool(regionSetupSeenKey, true);

  static Future<List<BatteryEntry>> readInventory() async {
    if (enableServerInventory) {
      // ユーザーのclient_idは送らず、GoにBearerトークンを渡して識別する。
      await WatchDenchiServerServices.auth.restoreOrCreate();
      final remote = await WatchDenchiServerServices.api.getBatteries();
      return remote.where((e) => e.quantity > 0).map((e) => BatteryEntry(
        id: e.id,
        type: e.type,
        manufacturer: e.manufacturer,
        quantity: e.quantity,
        location: e.storageLocation,
        chemistry: e.chemical ?? '不明',
      )).toList(growable: false);
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
    if (enableServerInventory) {
      throw StateError('サーバー在庫はGo APIでのみ変更できます。ローカル保存を停止しました');
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
    String municipality,
    Map<String, DateTime> dates, {
    String? municipalityCode,
    String? district,
    String? districtCode,
  }) async {
    await _prefs.setString(disposalKey, jsonEncode({
      'municipality': municipality,
      'municipalityCode': municipalityCode,
      'district': district,
      'districtCode': districtCode,
      'dates': dates.map(
        (key, value) => MapEntry(key, value.toIso8601String()),
      ),
    }));
  }
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

// -----------------------------------------------------------------------------
// ホームの下部に常時表示するタブ: 在庫棚 / 機器 / 回収日
// タブの選択はページ遷移ではなく IndexedStack で行うため、タブ状態を保持する。
// 新規の画像アセットや pubspec の追記なしで動くよう、ユーザー指定アイコンを
// 背景透明化・縮小した画像データとしてここに直接含めている。
// -----------------------------------------------------------------------------
const String _watchDenchiTvPngBase64 =
    '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';
const String _watchDenchiCalendarPngBase64 =
    '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';

class MainTabsPage extends StatefulWidget {
  const MainTabsPage({super.key});

  @override
  State<MainTabsPage> createState() => _MainTabsPageState();
}

class _MainTabsPageState extends State<MainTabsPage> {
  int _selectedIndex = 1; // 初期状態は中央の「機器」タブ。
  final GlobalKey<_InventoryPageState> _inventoryKey =
      GlobalKey<_InventoryPageState>();
  final GlobalKey<_HomePageState> _homeKey = GlobalKey<_HomePageState>();
  final GlobalKey<_DisposalPageState> _disposalKey =
      GlobalKey<_DisposalPageState>();

  void _selectTab(int nextIndex) {
    if (_selectedIndex == nextIndex) return;
    setState(() => _selectedIndex = nextIndex);
    // 戻ってきたタブはデータを読み直す。電池の追加/使用/交換が反映される。
    if (nextIndex == 0) {
      _inventoryKey.currentState?.loadEntries();
    } else if (nextIndex == 1) {
      _homeKey.currentState?.loadHome();
    } else if (nextIndex == 2) {
      _disposalKey.currentState?.loadSchedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: cream,
      child: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                InventoryPage(key: _inventoryKey),
                HomePage(key: _homeKey),
                DisposalPage(key: _disposalKey),
              ],
            ),
          ),
          // テキスト入力時はキーボードの後ろにタブを出さない。
          if (MediaQuery.of(context).viewInsets.bottom == 0)
            _WatchDenchiTabBar(
              selectedIndex: _selectedIndex,
              onSelected: _selectTab,
            ),
        ],
      ),
    );
  }
}

class _WatchDenchiTabBar extends StatelessWidget {
  const _WatchDenchiTabBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  static final MemoryImage _tvPng =
      MemoryImage(base64Decode(_watchDenchiTvPngBase64));
  static final MemoryImage _calendarPng =
      MemoryImage(base64Decode(_watchDenchiCalendarPngBase64));

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  Widget _tab({
    required int index,
    required String label,
    required Widget icon,
  }) {
    final active = selectedIndex == index;
    return Expanded(
      child: Semantics(
        label: '$label タブ',
        selected: active,
        button: true,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => onSelected(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 78),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFFE1EEDA)
                  : const Color(0x00FFFFFF),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 43, child: Center(child: icon)),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? const Color(0xFF527A60) : ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 3, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFFF1E7DA)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x16997B61),
              blurRadius: 18,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            _tab(
              index: 0,
              label: '在庫棚',
              icon: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SoftBattery(manufacturer: 'maxell', size: 39),
                  SizedBox(width: 3),
                  SoftBattery(manufacturer: 'Panasonic', size: 39),
                ],
              ),
            ),
            _tab(
              index: 1,
              label: '機器',
              icon: Image(
                image: _tvPng,
                width: 51,
                height: 42,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
            _tab(
              index: 2,
              label: '回収日',
              icon: Image(
                image: _calendarPng,
                width: 51,
                height: 42,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

  // 電池交換と手入力ステータスを両方操作できる。
  Future<void> openDeviceActions(DeviceUsage usage) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(usage.deviceName),
        message: Text(usage.type + '・' + usage.quantity.toString() + '本・' +
          usage.manufacturer + '　現在：' + usage.batteryStatus),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(popupContext).pop('status'),
            child: const Text('電池の状態を設定する'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(popupContext).pop('replace'),
            child: const Text('電池を交換する'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('キャンセル'),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'status') {
      await setDeviceBatteryStatus(usage);
    } else if (action == 'replace') {
      await chooseReplacement(usage);
    }
  }

  Future<void> setDeviceBatteryStatus(DeviceUsage usage) async {
    final chosen = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(usage.deviceName + 'の電池の状態'),
        message: const Text('使用状況をもとに手入力する状態です。残量や交換日を自動計測したものではありません。'),
        actions: [
          for (final state in const ['安心', '準備', '交換', '未設定'])
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(popupContext).pop(state),
              child: Text(state),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('キャンセル'),
        ),
      ),
    );
    if (!mounted || chosen == null) return;
    final index = devices.indexOf(usage);
    if (index < 0) return;
    final next = List<DeviceUsage>.from(devices);
    next[index] = usage.withBatteryStatus(chosen);
    try {
      await LocalBatteryStore.saveDevices(next);
      if (!mounted) return;
      setState(() => devices = next);
    } catch (error) {
      if (!mounted) return;
      await showError(context, '状態を保存できませんでした。');
    }
  }

  // 新しい電池を在庫棚から選び、同じ機器の使用履歴を継続する
  Future<void> chooseReplacement(DeviceUsage usage) async {
    if (enableServerInventory) {
      await showError(context, '交換APIはGo側で未実装です。サーバー試験モードでの交換は停止しています');
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
          '\n古い電池の履歴は残し、在庫には戻しません。',
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
        id: selected.id,
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

  @override
  Widget build(BuildContext context) {
    final activeDevices = devices.where((item) => item.isActive).toList();
    return CupertinoPageScaffold(
      backgroundColor: cream,
      child: SafeArea(
        child: loading
            ? const Center(child: CupertinoActivityIndicator())
            // 空のときはスクロールリスト内ではなく、タブバーを除く画面中央に表示。
            : activeDevices.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.house_alt,
                              color: Color(0xFFC09A7D), size: 52),
                          SizedBox(height: 17),
                          Text('使用している機器はありません',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: ink, fontSize: 17,
                                  fontWeight: FontWeight.w600)),
                          SizedBox(height: 9),
                          Text('在庫棚から電池を選んで登録',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: mutedInk, fontSize: 14)),
                        ],
                      ),
                    ),
                  )
                : CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: 19),
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
                                              // 元の機器アイコンと重ねて右上に電池ステータスを配置。
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
                                                          borderRadius: BorderRadius.circular(25),
                                                          border: Border.all(color: const Color(0xFFF0CCC5)),
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
                                                      child: _PresentationBatteryStatusBadge(
                                                        status: usage.batteryStatus,
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

// -----------------------------------------------------------------------------
// 地域検索の候補データ。市町村と収集地区は別々に検索・選択する。
// 市町村候補 = 沖縄県の行政区分 (処分データの対応状況を示すものではない)。
// 収集地区候補 = 武ちゃんの確認済みデータを後から追加する場所。
// 架空の地区や収集日を表示しない。
// -----------------------------------------------------------------------------
class DisposalAreaOption {
  const DisposalAreaOption(this.code, this.name, this.reading);

  final String code;
  final String name;
  final String reading;

  bool matches(String input) {
    final q = input.replaceAll(RegExp(r'[\s　]'), '').toLowerCase();
    if (q.isEmpty) return true;
    return name.replaceAll('　', '').toLowerCase().contains(q) ||
        reading.replaceAll('　', '').toLowerCase().contains(q);
  }
}

class DisposalAreaCatalog {
  DisposalAreaCatalog._();

  // 沖縄県の41市町村。codeは市区町村コード。
  static const List<DisposalAreaOption> municipalities = [
    DisposalAreaOption('47201', '那覇市', 'なはし'),
    DisposalAreaOption('47205', '宜野湾市', 'ぎのわんし'),
    DisposalAreaOption('47207', '石垣市', 'いしがきし'),
    DisposalAreaOption('47208', '浦添市', 'うらそえし'),
    DisposalAreaOption('47209', '名護市', 'なごし'),
    DisposalAreaOption('47210', '糸満市', 'いとまんし'),
    DisposalAreaOption('47211', '沖縄市', 'おきなわし'),
    DisposalAreaOption('47212', '豊見城市', 'とみぐすくし'),
    DisposalAreaOption('47213', 'うるま市', 'うるまし'),
    DisposalAreaOption('47214', '宮古島市', 'みやこじまし'),
    DisposalAreaOption('47215', '南城市', 'なんじょうし'),
    DisposalAreaOption('47301', '国頭村', 'くにがみそん'),
    DisposalAreaOption('47302', '大宜味村', 'おおぎみそん'),
    DisposalAreaOption('47303', '東村', 'ひがしそん'),
    DisposalAreaOption('47306', '今帰仁村', 'なきじんそん'),
    DisposalAreaOption('47308', '本部町', 'もとぶちょう'),
    DisposalAreaOption('47311', '恩納村', 'おんなそん'),
    DisposalAreaOption('47313', '宜野座村', 'ぎのざそん'),
    DisposalAreaOption('47314', '金武町', 'きんちょう'),
    DisposalAreaOption('47315', '伊江村', 'いえそん'),
    DisposalAreaOption('47324', '読谷村', 'よみたんそん'),
    DisposalAreaOption('47325', '嘉手納町', 'かでなちょう'),
    DisposalAreaOption('47326', '北谷町', 'ちゃたんちょう'),
    DisposalAreaOption('47327', '北中城村', 'きたなかぐすくそん'),
    DisposalAreaOption('47328', '中城村', 'なかぐすくそん'),
    DisposalAreaOption('47329', '西原町', 'にしはらちょう'),
    DisposalAreaOption('47348', '与那原町', 'よなばるちょう'),
    DisposalAreaOption('47350', '南風原町', 'はえばるちょう'),
    DisposalAreaOption('47353', '渡嘉敷村', 'とかしきそん'),
    DisposalAreaOption('47354', '座間味村', 'ざまみそん'),
    DisposalAreaOption('47355', '粟国村', 'あぐにそん'),
    DisposalAreaOption('47356', '渡名喜村', 'となきそん'),
    DisposalAreaOption('47357', '南大東村', 'みなみだいとうそん'),
    DisposalAreaOption('47358', '北大東村', 'きただいとうそん'),
    DisposalAreaOption('47359', '伊平屋村', 'いへやそん'),
    DisposalAreaOption('47360', '伊是名村', 'いぜなそん'),
    DisposalAreaOption('47361', '久米島町', 'くめじまちょう'),
    DisposalAreaOption('47362', '八重瀬町', 'やえせちょう'),
    DisposalAreaOption('47375', '多良間村', 'たらまそん'),
    DisposalAreaOption('47381', '竹富町', 'たけとみちょう'),
    DisposalAreaOption('47382', '与那国町', 'よなぐにちょう'),
  ];

  // TODO(地域データ): 武ちゃんの取得結果をここに差し込む。
  // キーは上の市町村コード。値はその市町村の収集地区候補。
  // 例のダミー地区は登録しない。確認できた正式な地区のみ追加する。
  // データ形式: '47201': [DisposalAreaOption('地区ID', '地区名', 'ふりがな')],
  // 実際に分別ルールを案内できる自治体だけを初期画面に表示する。
  static const List<DisposalAreaOption> supportedMunicipalities = [
    DisposalAreaOption('47201', '那覇市', 'なはし'),
    DisposalAreaOption('47326', '北谷町', 'ちゃたんちょう'),
  ];

  static const Map<String, List<DisposalAreaOption>> districtsByCityCode = {
    '47201': [
      DisposalAreaOption('naha-makishi-1', '牧志1丁目', 'まきしいっちょうめ'),
      DisposalAreaOption('naha-makishi-2', '牧志2丁目', 'まきしにちょうめ'),
      DisposalAreaOption('naha-makishi-3', '牧志3丁目', 'まきしさんちょうめ'),
      DisposalAreaOption('naha-omoromachi-1', 'おもろまち1丁目', 'おもろまちいっちょうめ'),
      DisposalAreaOption('naha-omoromachi-2', 'おもろまち2丁目', 'おもろまちにちょうめ'),
      DisposalAreaOption('naha-omoromachi-3', 'おもろまち3丁目', 'おもろまちさんちょうめ'),
      DisposalAreaOption('naha-omoromachi-4', 'おもろまち4丁目', 'おもろまちよんちょうめ'),
      DisposalAreaOption('naha-oroku-1', '小禄1丁目', 'おろくいっちょうめ'),
      DisposalAreaOption('naha-oroku-2', '小禄2丁目', 'おろくにちょうめ'),
      DisposalAreaOption('naha-oroku-3', '小禄3丁目', 'おろくさんちょうめ'),
    ],
    '47326': [
      DisposalAreaOption('chatan-mihama-1', '美浜1丁目', 'みはまいっちょうめ'),
      DisposalAreaOption('chatan-mihama-2', '美浜2丁目', 'みはまにちょうめ'),
      DisposalAreaOption('chatan-mihama-3', '美浜3丁目', 'みはまさんちょうめ'),
      DisposalAreaOption('chatan-chatan-1', '北谷1丁目', 'ちゃたんいっちょうめ'),
      DisposalAreaOption('chatan-chatan-2', '北谷2丁目', 'ちゃたんにちょうめ'),
      DisposalAreaOption('chatan-kuwae-1', '桑江1丁目', 'くわえいっちょうめ'),
      DisposalAreaOption('chatan-ihei-1', '伊平1丁目', 'いへいいっちょうめ'),
      DisposalAreaOption('chatan-ihei-2', '伊平2丁目', 'いへいにちょうめ'),
    ],
  };

  static List<DisposalAreaOption> search(
      List<DisposalAreaOption> options, String query) {
    return options.where((item) => item.matches(query)).take(6).toList();
  }

  static List<DisposalAreaOption> districtsFor(String cityCode) =>
      districtsByCityCode[cityCode] ?? const <DisposalAreaOption>[];

  static DisposalAreaOption? findMunicipality(String? code, String? name) {
    for (final item in municipalities) {
      if (code != null && code == item.code) return item;
      if (code == null && name == item.name) return item;
    }
    return null;
  }
}

// 初回起動時の地域登録画面。日程・分別のダミーデータは生成しない。
// 市町村候補は固定リスト、収集地区はあとから武ちゃんの確定データを追加する。
class RegionSetupPage extends StatefulWidget {
  const RegionSetupPage({super.key});

  @override
  State<RegionSetupPage> createState() => _RegionSetupPageState();
}

class _RegionSetupPageState extends State<RegionSetupPage> {
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final FocusNode _cityFocus = FocusNode();
  final FocusNode _districtFocus = FocusNode();
  DisposalAreaOption? _city;
  DisposalAreaOption? _district;
  bool _showCityCandidates = false;
  bool _showDistrictCandidates = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restoreRegion();
  }

  Future<void> _restoreRegion() async {
    try {
      final saved = await LocalBatteryStore.readDisposalSchedule();
      final previous = DisposalAreaCatalog.findMunicipality(
        saved['municipalityCode'] as String?,
        saved['municipality'] as String?,
      );
      if (previous == null ||
          !DisposalAreaCatalog.supportedMunicipalities
              .any((item) => item.code == previous.code)) return;
      DisposalAreaOption? district;
      for (final option in DisposalAreaCatalog.districtsFor(previous.code)) {
        if (option.code == saved['districtCode'] ||
            option.name == saved['district']) {
          district = option;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _city = previous;
        _district = district;
        _cityController.text = previous.name;
        _districtController.text = district?.name ?? '';
      });
    } catch (error) {
      debugPrint('保存済み地域を復元できませんでした: $error');
    }
  }

  @override
  void dispose() {
    _cityController.dispose();
    _districtController.dispose();
    _cityFocus.dispose();
    _districtFocus.dispose();
    super.dispose();
  }

  void _chooseCity(DisposalAreaOption city) {
    setState(() {
      _city = city;
      _district = null;
      _cityController.text = city.name;
      _districtController.clear();
      _showCityCandidates = false;
      _showDistrictCandidates = false;
      _error = null;
    });
    _cityFocus.unfocus();
  }

  void _chooseDistrict(DisposalAreaOption district) {
    setState(() {
      _district = district;
      _districtController.text = district.name;
      _showDistrictCandidates = false;
      _error = null;
    });
    _districtFocus.unfocus();
  }

  void _enterHome() {
    Navigator.of(context).pushReplacement(
      CupertinoPageRoute<void>(builder: (_) => const MainTabsPage()),
    );
  }

  Future<void> _registerRegion() async {
    final city = _city;
    if (city == null || _cityController.text.trim() != city.name) {
      setState(() => _error = '候補をタップして市町村を選んでね');
      return;
    }
    final districts = DisposalAreaCatalog.districtsFor(city.code);
    if (districts.isNotEmpty &&
        (_district == null ||
            _districtController.text.trim() != _district!.name)) {
      setState(() => _error = '候補をタップして収集地区を選んでね');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 回収日は未登録。自治体の正式データが届くまで推測しない。
      await LocalBatteryStore.saveDisposalSchedule(
        city.name,
        const <String, DateTime>{},
        municipalityCode: city.code,
        district: _district?.name,
        districtCode: _district?.code,
      );
      await LocalBatteryStore.markRegionSetupSeen();
      if (!mounted) return;
      _enterHome();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '地域を保存できませんでした。もう一度試してね。';
      });
    }
  }

  Widget _suggestions(
    List<DisposalAreaOption> options,
    void Function(DisposalAreaOption) onSelect,
  ) => Container(
        margin: const EdgeInsets.only(top: 7),
        decoration: BoxDecoration(
          color: paper,
          border: Border.all(color: const Color(0xFFE6D9C8)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0)
                Container(height: 1, color: const Color(0xFFF0E6DA)),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                    horizontal: 15, vertical: 12),
                onPressed: () => onSelect(options[i]),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.location,
                        color: coral, size: 19),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(options[i].name,
                          style: const TextStyle(
                              color: ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ),
                    const Icon(CupertinoIcons.chevron_right,
                        color: mutedInk, size: 15),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cityOptions = DisposalAreaCatalog.search(
        DisposalAreaCatalog.supportedMunicipalities, _cityController.text);
    final districts = _city == null
        ? const <DisposalAreaOption>[]
        : DisposalAreaCatalog.districtsFor(_city!.code);
    final districtOptions = DisposalAreaCatalog.search(
        districts, _districtController.text);
    final canRegister = _city != null &&
        _cityController.text.trim() == _city!.name &&
        (districts.isEmpty ||
            (_district != null &&
                _districtController.text.trim() == _district!.name));

    return CupertinoPageScaffold(
      backgroundColor: cream,
      navigationBar: const CupertinoNavigationBar(
        backgroundColor: cream,
        border: null,
        middle: Text('はじめに', style: TextStyle(color: ink)),
      ),
      child: SafeArea(
        // フォームが収まるときは縦中央、候補表示やキーボードで長くなればスクロール。
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: viewport.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: const Color(0xFFF3DDD3),
                borderRadius: BorderRadius.circular(21),
              ),
              child: const Icon(CupertinoIcons.location_solid,
                  color: coral, size: 34),
            ),
            const SizedBox(height: 22),
            const Text('お住まいの地域を教えてね',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800, color: ink)),
            const SizedBox(height: 9),
            const Text('電池の捨て方を地域に合わせて案内するため、\nまずは市町村を登録しよう。',
                style: TextStyle(color: mutedInk, fontSize: 14, height: 1.55)),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8DB),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Row(
                children: [
                  Icon(CupertinoIcons.location_solid,
                      color: coral, size: 19),
                  SizedBox(width: 10),
                  Expanded(child: Text('沖縄県', style: TextStyle(
                      color: ink, fontWeight: FontWeight.w700))),
                  Icon(CupertinoIcons.lock, color: mutedInk, size: 16),
                ],
              ),
            ),
            const SizedBox(height: 21),
            const Text('市町村を選択',
                style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            Row(children: [
              for (final city in DisposalAreaCatalog.supportedMunicipalities) ...[
                Expanded(child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  color: _city?.code == city.code ? coral : paper,
                  borderRadius: BorderRadius.circular(14),
                  onPressed: () => _chooseCity(city),
                  child: Text(city.name, style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: _city?.code == city.code ? CupertinoColors.white : ink,
                  )),
                )),
                if (city.code == '47201') const SizedBox(width: 9),
              ],
            ]),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: _cityController,
              focusNode: _cityFocus,
              placeholder: '例：那覇、なは、沖縄…',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 15, right: 9),
                child: Icon(CupertinoIcons.search, color: coral),
              ),
              suffix: _city == null
                  ? null
                  : const Padding(
                      padding: EdgeInsets.only(right: 13),
                      child: Icon(CupertinoIcons.check_mark_circled_solid,
                          color: Color(0xFF6E9273)),
                    ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              style: const TextStyle(color: ink, fontSize: 15),
              decoration: BoxDecoration(
                color: paper,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: _city == null
                    ? const Color(0xFFE6D9C8)
                    : const Color(0xFF9EC2A5)),
              ),
              onTap: () => setState(() => _showCityCandidates = true),
              onChanged: (_) => setState(() {
                _city = null;
                _district = null;
                _districtController.clear();
                _showCityCandidates = true;
                _showDistrictCandidates = false;
                _error = null;
              }),
            ),
            if (_showCityCandidates)
              if (cityOptions.isNotEmpty)
                _suggestions(cityOptions, _chooseCity)
              else
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('一致する市町村がありません。',
                      style: TextStyle(color: mutedInk)),
                ),
            if (_city != null) ...[
              const SizedBox(height: 22),
              const Text('収集地区',
                  style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              if (districts.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: paper,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: const Color(0xFFE6D9C8)),
                  ),
                  child: const Row(
                    children: [
                      Icon(CupertinoIcons.clock, color: mutedInk),
                      SizedBox(width: 10),
                      Expanded(child: Text('地区データを準備中',
                          style: TextStyle(color: mutedInk))),
                    ],
                  ),
                )
              else ...[
                CupertinoTextField(
                  controller: _districtController,
                  focusNode: _districtFocus,
                  placeholder: '地区名の一部を入力',
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 15, right: 9),
                    child: Icon(CupertinoIcons.search, color: coral),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: paper,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: const Color(0xFFE6D9C8)),
                  ),
                  onTap: () => setState(() => _showDistrictCandidates = true),
                  onChanged: (_) => setState(() {
                    _district = null;
                    _showDistrictCandidates = true;
                    _error = null;
                  }),
                ),
                if (_showDistrictCandidates || _district == null)
                  if (districtOptions.isNotEmpty)
                    _suggestions(districtOptions, _chooseDistrict)
                  else
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text('一致する地区がありません。',
                          style: TextStyle(color: mutedInk)),
                    ),
              ],
              const SizedBox(height: 9),
              Text(districts.isEmpty
                  ? '地区別の収集情報は準備中。今は市町村だけ登録できるよ。'
                  : '地区名も候補から選択してね。',
                  style: const TextStyle(color: mutedInk, fontSize: 12)),
            ],
            const SizedBox(height: 18),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: coral)),
            ],
            const SizedBox(height: 25),
            CupertinoButton.filled(
              onPressed: _saving || !canRegister ? null : _registerRegion,
              child: Text(_saving ? '保存中…' : 'この地域で始める'),
            ),
            const SizedBox(height: 13),
            const Text('回収日・処分方法は公式情報が確認できた地域だけ表示するよ。',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedInk, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 電池の捨て方・回収日
class DisposalPage extends StatefulWidget {
  const DisposalPage({super.key});

  @override
  State<DisposalPage> createState() => _DisposalPageState();
}

class _DisposalPageState extends State<DisposalPage> {
  final TextEditingController municipalityController = TextEditingController();
  final TextEditingController districtController = TextEditingController();
  final FocusNode municipalityFocus = FocusNode();
  final FocusNode districtFocus = FocusNode();
  final Map<String, DateTime> dates = {};
  DisposalAreaOption? selectedMunicipality;
  DisposalAreaOption? selectedDistrict;
  String registeredMunicipality = '';
  String? registeredDistrict;
  bool citySuggestionsVisible = false;
  bool districtSuggestionsVisible = false;
  String selectedType = 'dry';
  bool loading = true;
  bool saving = false;
  bool saved = false;
  String? error;

  static const List<Map<String, String>> categories = [
    {'key': 'dry', 'name': '乾電池'},
    {'key': 'coin', 'name': 'コイン形'},
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
    districtController.dispose();
    municipalityFocus.dispose();
    districtFocus.dispose();
    super.dispose();
  }

  // 那覇市公式収集日表：牧志1〜3丁目、もやさないごみ・危険ごみ・乾電池は第2・4月曜。
  static DateTime nextNahaCollectionDate(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    for (var offset = 0; offset < 65; offset++) {
      final date = today.add(Duration(days: offset));
      final nth = ((date.day - 1) ~/ 7) + 1;
      if (date.weekday == DateTime.monday && (nth == 2 || nth == 4)) {
        return date;
      }
    }
    throw StateError('収集日を計算できませんでした');
  }

  Future<void> loadSchedule() async {
    // 他の地域から持ち込んだ古いデータを表示せず、公式表の対象地区に固定。
    if (!mounted) return;
    const target = DisposalAreaOption(
        'naha-makishi-1', '牧志1丁目', 'まきしいっちょうめ');
    setState(() {
      selectedMunicipality =
          DisposalAreaCatalog.findMunicipality('47201', '那覇市');
      selectedDistrict = target;
      registeredMunicipality = '那覇市';
      registeredDistrict = target.name;
      municipalityController.text = '那覇市';
      districtController.text = target.name;
      loading = false;
      error = null;
    });
  }

  Future<void> chooseDate() async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('那覇市・牧志1丁目の収集日'),
        content: const Text(
            '乾電池・コイン電池・充電式電池は毎月第2・第4月曜日が対象の収集日です。'
            '回収区分と袋は種類によって異なります。臨時変更は那覇市公式サイトをご確認ください。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  void _selectMunicipality(DisposalAreaOption option) {
    final oldCity = selectedMunicipality?.code;
    setState(() {
      if (oldCity != option.code && registeredMunicipality != option.name) {
        // 他の市町村の回収予定日を流用しない。
        dates.clear();
      }
      selectedMunicipality = option;
      selectedDistrict = null;
      municipalityController.text = option.name;
      districtController.clear();
      citySuggestionsVisible = false;
      districtSuggestionsVisible = false;
      saved = false;
      error = null;
    });
    municipalityFocus.unfocus();
  }

  void _selectDistrict(DisposalAreaOption option) {
    setState(() {
      if (selectedDistrict?.code != option.code &&
          registeredDistrict != option.name) {
        dates.clear();
      }
      selectedDistrict = option;
      districtController.text = option.name;
      districtSuggestionsVisible = false;
      saved = false;
      error = null;
    });
    districtFocus.unfocus();
  }

  Future<void> saveSchedule() async {
    final city = selectedMunicipality;
    if (city == null || municipalityController.text.trim() != city.name) {
      setState(() => error = '検索候補をタップして市町村を選んでね');
      return;
    }
    final districtOptions = DisposalAreaCatalog.districtsFor(city.code);
    if (districtOptions.isNotEmpty &&
        (selectedDistrict == null ||
         districtController.text.trim() != selectedDistrict!.name)) {
      setState(() => error = '検索候補から収集地区を選んでね');
      return;
    }
    final regionChanged = city.name != registeredMunicipality ||
        selectedDistrict?.name != registeredDistrict;
    // 手入力の予定日は任意。地区が変わったときの以前の予定日は保存しない。
    final safeDates = {...dates};
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await LocalBatteryStore.saveDisposalSchedule(
        city.name,
        safeDates,
        municipalityCode: city.code,
        district: selectedDistrict?.name,
        districtCode: selectedDistrict?.code,
      );
      if (!mounted) return;
      setState(() {
        if (regionChanged) {
          dates..clear()..addAll(safeDates);
        }
        registeredMunicipality = city.name;
        registeredDistrict = selectedDistrict?.name;
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

  Widget _suggestionList(
    List<DisposalAreaOption> options,
    void Function(DisposalAreaOption) onSelect,
  ) => Container(
        margin: const EdgeInsets.only(top: 7),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6D9C8)),
        ),
        child: Column(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0)
                Container(height: 1, color: const Color(0xFFF0E6DA)),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                onPressed: () => onSelect(options[i]),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.location,
                        color: Color(0xFFCC706B), size: 19),
                    const SizedBox(width: 11),
                    Expanded(child: Text(options[i].name,
                        style: const TextStyle(color: ink, fontSize: 15,
                            fontWeight: FontWeight.w600))),
                    const Icon(CupertinoIcons.chevron_right,
                        color: mutedInk, size: 15),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  /// 公式サイトを外部ブラウザで開く。ポップアップ制限などで失敗したらURLをコピー。
  Future<void> openOfficialGuide(String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (error) {
      debugPrint('公式サイトの起動に失敗: $error');
    }
    if (!mounted) return;
    try {
      await Clipboard.setData(ClipboardData(text: url));
    } catch (error) {
      debugPrint('URLのコピーにも失敗: $error');
      if (!mounted) return;
      await showError(context, '公式サイトを開けませんでした。通信状況を確認してね。');
      return;
    }
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('公式サイトを開けませんでした'),
        content: const Text('URLをコピーしたよ。ブラウザに貼り付けて開いてね。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // 電池の種類別に、長い説明文ではなく2ステップで案内。
  // 分別や回収可否は自治体・回収店によって異なるため、固定の収集日を作らない。
  String get selectedBatteryLabel =>
      categories.firstWhere((item) => item['key'] == selectedType)['name']!;

  String get batteryExample {
    switch (selectedType) {
      case 'dry':
        return '単1〜単5形';
      case 'coin':
        return 'CR2032など';
      case 'recharge':
        return 'ニッケル水素など';
      default:
        return '電池';
    }
  }

  List<String> get disposalSteps {
    switch (selectedType) {
      case 'dry':
        return ['マンガン・アルカリ乾電池を区別してまとめる', '透明・半透明の袋で第2・4月曜日に出す'];
      case 'coin':
        return ['CR・BR形は電極をテープで絶縁', '乾電池と同じ収集日に透明袋で出す'];
      case 'recharge':
        return ['露出した金属端子をテープで絶縁', '乾電池と別袋に入れ「きけんごみ」で出す'];
      default:
        return ['電極を絶縁', '自治体の案内を確認する'];
    }
  }

  String get disposalFootnote => selectedType == 'recharge'
      ? '那覇市では2026年3月から充電式電池の単体収集を開始。回収協力店への持ち込みも可能。'
      : 'この案内は那覇市・牧志1丁目のみのルールです。';

  Widget _guideStep(int number, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFCC706B),
                shape: BoxShape.circle,
              ),
              child: Text('$number',
                  style: const TextStyle(color: CupertinoColors.white,
                      fontSize: 14, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: number == 1 ? const Color(0xFFA7544E) : ink,
                  fontSize: 15,
                  fontWeight: number == 1 ? FontWeight.w700 : FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );

  // 回収日画面の右上メニュー。カレンダー・種類・捨て方は常に画面に残す。
  Future<void> _showDisposalMenu() async {
    final option = await showCupertinoModalPopup<String>(
      context: context,
      builder: (menuContext) => CupertinoActionSheet(
        title: const Text('那覇市・牧志1丁目'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(menuContext).pop('collection'),
            child: const Text('収集日について'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(menuContext).pop('official'),
            child: const Text('那覇市の公式案内'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(menuContext).pop(),
          child: const Text('キャンセル'),
        ),
      ),
    );
    if (!mounted) return;
    if (option == 'collection') {
      await chooseDate();
    } else if (option == 'official') {
      await openOfficialGuide(
        'https://www.city.naha.okinawa.jp/kurasitetuduki/gomi-recycling/1001934/1008614.html');
    }
  }

  // もともとの地域検索・登録処理をそのまま使い、表示場所だけ移動する。
  // ignore: unused_element
  Future<void> _showRegionSettings() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (popupContext) => StatefulBuilder(
        builder: (sheetContext, sheetSetState) {
          final keyboardHeight = MediaQuery.viewInsetsOf(sheetContext).bottom;
          final usableHeight = MediaQuery.sizeOf(sheetContext).height - keyboardHeight;
          return Padding(
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 540),
                height: usableHeight * 0.84,
                decoration: const BoxDecoration(
                  color: cream,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(27)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 17, 13, 9),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('お住まいの地域', style: TextStyle(
                              color: ink, fontSize: 20, fontWeight: FontWeight.w800,
                              decoration: TextDecoration.none,
                            )),
                          ),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            onPressed: () => Navigator.of(popupContext).pop(),
                            child: const Text('完了', style: TextStyle(
                              color: coral, fontWeight: FontWeight.w700,
                            )),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
                        child: _buildRegionSettings(sheetContext, sheetSetState),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Future<void> _showOfficialGuides() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: const Text('公式の案内'),
        message: const Text('電池の捨て方や回収場所は公式情報を確認してね。'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(popupContext).pop();
              openOfficialGuide('https://www.baj.or.jp/reuse_and_recycle/recycle/disposal.html');
            },
            child: const Text('電池工業会・捨て方ナビ'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(popupContext).pop();
              openOfficialGuide('https://www.jbrc.com/general/recycle_kensaku/');
            },
            child: const Text('JBRC・回収協力店を探す'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('閉じる'),
        ),
      ),
    );
  }

  Widget _buildRegionSettings(BuildContext sheetContext, StateSetter sheetSetState) {
    final cityHasChanged = selectedMunicipality?.name != registeredMunicipality ||
        selectedDistrict?.name != registeredDistrict;
    final availableDistricts = selectedMunicipality == null
        ? const <DisposalAreaOption>[]
        : DisposalAreaCatalog.districtsFor(selectedMunicipality!.code);
    final citySuggestions = DisposalAreaCatalog.search(
        DisposalAreaCatalog.municipalities, municipalityController.text);
    final districtSuggestions = DisposalAreaCatalog.search(
        availableDistricts, districtController.text);
    final savedRegionText = '保存したよ！ 沖縄県 ' +
        (selectedMunicipality?.name ?? '') +
        (selectedDistrict == null ? '' : '・' + selectedDistrict!.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
                  // 4. オートコンプリート：候補をタップして正規の地域IDを確定する。
                  const _FieldTitle('お住まいの地域'),
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8DB),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      children: [
                        Icon(CupertinoIcons.location_solid,
                            size: 19, color: Color(0xFFCC706B)),
                        SizedBox(width: 10),
                        Expanded(child: Text('沖縄県',
                            style: TextStyle(color: ink, fontSize: 15,
                                fontWeight: FontWeight.w700))),
                        Icon(CupertinoIcons.lock,
                            size: 15, color: mutedInk),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text('市町村を検索', style: TextStyle(
                      color: ink, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 7),
                  CupertinoTextField(
                    controller: municipalityController,
                    focusNode: municipalityFocus,
                    placeholder: '例：那覇、なは、浦添…',
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 15, right: 9),
                      child: Icon(CupertinoIcons.search,
                          color: Color(0xFFCC706B), size: 20),
                    ),
                    suffix: selectedMunicipality == null
                        ? null
                        : const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Icon(CupertinoIcons.check_mark_circled_solid,
                                color: Color(0xFF6E9273), size: 19)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFDF9),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: selectedMunicipality == null
                          ? const Color(0xFFE6D9C8)
                          : const Color(0xFF9EC2A5)),
                    ),
                    style: const TextStyle(color: ink, fontSize: 15),
                    onTap: () {
                      setState(() => citySuggestionsVisible = true);
                      sheetSetState(() {});
                    },
                    onChanged: (_) {
                      setState(() {
                      selectedMunicipality = null;
                      selectedDistrict = null;
                      districtController.clear();
                      citySuggestionsVisible = true;
                      districtSuggestionsVisible = false;
                      saved = false;
                      error = null;
                    });
                    sheetSetState(() {});
                  },
                  ),
                  if (citySuggestionsVisible && selectedMunicipality == null)
                    if (citySuggestions.isNotEmpty)
                      _suggestionList(citySuggestions, (option) {
                        _selectMunicipality(option);
                        sheetSetState(() {});
                      })
                    else
                      const Padding(
                        padding: EdgeInsets.only(top: 9),
                        child: Text('一致する市町村がありません。名前の一部で検索してね。',
                            style: TextStyle(color: mutedInk, fontSize: 12)),
                      ),
                  if (selectedMunicipality != null) ...[
                    const SizedBox(height: 16),
                    const Text('収集地区を検索', style: TextStyle(
                        color: ink, fontSize: 14,
                        fontWeight: FontWeight.w700)),
                    const SizedBox(height: 7),
                    if (availableDistricts.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 15),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFDF9),
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(color: const Color(0xFFE6D9C8)),
                        ),
                        child: const Row(
                          children: [
                            Icon(CupertinoIcons.search,
                                size: 19, color: mutedInk),
                            SizedBox(width: 10),
                            Expanded(child: Text('地区データを準備中',
                                style: TextStyle(color: mutedInk,
                                    fontSize: 14))),
                            Icon(CupertinoIcons.clock,
                                color: mutedInk, size: 17),
                          ],
                        ),
                      )
                    else ...[
                      CupertinoTextField(
                        controller: districtController,
                        focusNode: districtFocus,
                        placeholder: '地区名の一部を入力',
                        prefix: const Padding(
                          padding: EdgeInsets.only(left: 15, right: 9),
                          child: Icon(CupertinoIcons.search,
                              color: Color(0xFFCC706B), size: 20),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFDF9),
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(color: const Color(0xFFE6D9C8)),
                        ),
                        onTap: () {
                            setState(() => districtSuggestionsVisible = true);
                            sheetSetState(() {});
                          },
                        onChanged: (_) {
                      setState(() {
                          selectedDistrict = null;
                          districtSuggestionsVisible = true;
                          saved = false;
                          error = null;
                        });
                        sheetSetState(() {});
                      },
                      ),
                      if (districtSuggestionsVisible && selectedDistrict == null)
                        if (districtSuggestions.isNotEmpty)
                          _suggestionList(districtSuggestions, (option) {
                            _selectDistrict(option);
                            sheetSetState(() {});
                          })
                        else
                          const Padding(
                            padding: EdgeInsets.only(top: 9),
                            child: Text('該当する地区がありません。',
                                style: TextStyle(color: mutedInk,
                                    fontSize: 12)),
                          ),
                    ],
                    const SizedBox(height: 9),
                    Text(availableDistricts.isEmpty
                        ? '地区別データは未接続。今は市町村だけ登録できるよ。回収日は自動表示されません。'
                        : '地区を候補から選ぶと、地域が確定するよ。',
                        style: const TextStyle(color: mutedInk,
                            fontSize: 11.5, height: 1.5)),
                  ],
                  if (cityHasChanged && registeredMunicipality.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    const Text('地域を変更する場合、以前の回収予定日は引き継がれないよ。',
                        style: TextStyle(color: coral, fontSize: 12)),
                  ],
                  const SizedBox(height: 10),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(CupertinoIcons.lock, size: 13, color: mutedInk),
                      SizedBox(width: 7),
                      Expanded(child: Text('番地・部屋番号は不要。地域はこの端末に保存されるよ。',
                          style: TextStyle(color: mutedInk,
                              fontSize: 11.5, fontWeight: FontWeight.w600))),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (error != null) ...[
                    Text(error!, style: const TextStyle(
                        color: coral, fontSize: 12)),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      onPressed: saving || selectedMunicipality == null ||
                              (availableDistricts.isNotEmpty &&
                               selectedDistrict == null)
                          ? null : () async {
                              final task = saveSchedule();
                              sheetSetState(() {});
                              await task;
                              if (sheetContext.mounted) sheetSetState(() {});
                            },
                      child: Text(saving ? '保存中…' : 'この地域を保存する'),
                    ),
                  ),
                  if (saved) ...[
                    const SizedBox(height: 9),
                    Center(child: Text(
                        savedRegionText,
                        style: const TextStyle(color: Color(0xFF6E9273),
                            fontSize: 13, fontWeight: FontWeight.w700))),
                  ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final next = nextNahaCollectionDate(DateTime.now());
    final steps = disposalSteps;
    return CupertinoPageScaffold(
      backgroundColor: cream,
      child: SafeArea(
        child: loading
            ? const Center(child: CupertinoActivityIndicator())
            : Stack(
                children: [
                  ListView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 45),
                children: [
                  // 1. 日めくりカレンダーを画面の最上部に。ここから日付を変更できる。
                  PickupTearOffCalendar(
                    date: next,
                    batteryType: selectedBatteryLabel,
                    onEdit: chooseDate,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    decoration: BoxDecoration(
                      color: paper,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE6D9C8)),
                    ),
                    child: Row(children: [
                      const Icon(CupertinoIcons.location_solid, color: coral, size: 17),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('那覇市・牧志1丁目  毎月第2・4月曜日',
                            style: TextStyle(color: ink, fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                      CupertinoButton(
                        minSize: 0,
                        padding: const EdgeInsets.all(4),
                        onPressed: () => openOfficialGuide(
                          'https://www.city.naha.okinawa.jp/kurasitetuduki/gomi-recycling/1001934/1008614.html',
                        ),
                        child: const Icon(CupertinoIcons.link, size: 18, color: coral),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 22),
                  // 2. 電池の種類（画像と同じ横並びの丸いタブ）
                  const _FieldTitle('電池の種類'),
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 47,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final category in categories)
                          Padding(
                            padding: const EdgeInsets.only(right: 9),
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 19),
                              color: selectedType == category['key']
                                  ? const Color(0xFFCC706B)
                                  : const Color(0xFFFFFDF9),
                              borderRadius: BorderRadius.circular(19),
                              onPressed: () => setState(() {
                                selectedType = category['key']!;
                                saved = false;
                                error = null;
                              }),
                              child: Text(
                                category['name']!,
                                style: TextStyle(
                                  color: selectedType == category['key']
                                      ? CupertinoColors.white : ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  // 3. 電池の種類を切り替えた直後に、その電池の捨て方を表示する
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFDF9),
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text('捨てるときのポイント',
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  )),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4E4DB),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                batteryExample,
                                style: const TextStyle(
                                  color: Color(0xFF9E584C),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 17),
                        _guideStep(1, steps[0]),
                        _guideStep(2, steps[1]),
                        Container(
                          height: 1,
                          color: const Color(0xFFE9DDCE),
                          margin: const EdgeInsets.only(top: 2, bottom: 13),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(CupertinoIcons.info_circle,
                                  color: mutedInk, size: 16),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(disposalFootnote,
                                  style: const TextStyle(
                                    color: mutedInk,
                                    fontSize: 12,
                                    height: 1.45,
                                    fontWeight: FontWeight.w500,
                                  )),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
                  ),
                  Positioned(
                    top: 0,
                    right: 15,
                    child: Semantics(
                      label: '回収日の設定・案内',
                      button: true,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: paper,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE6D9C8)),
                        ),
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: _showDisposalMenu,
                          child: const Icon(CupertinoIcons.ellipsis,
                              color: ink, size: 24),
                        ),
                      ),
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
        await showError(context, 'Go APIへ登録する場合、保管場所の入力が必要です');
        return;
      }
      // 2026-11-19確認のGo mainにはchemical列/入力処理がない。
      // APIは未知のJSONキーを無視するため、黙って保存済みに見せない。
      final proceed = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Go API 接続テスト'),
          content: const Text(
            '今のGo側には電池の中身（chemical）の保存処理がまだありません。'
            'このテスト登録では本数やメーカーはDBに保存されますが、'
            '電池の中身は保存されません。テスト登録しますか？',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('やめる'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('テスト登録'),
            ),
          ],
        ),
      );
      if (!mounted || proceed != true) return;
      try {
        await WatchDenchiServerServices.auth.restoreOrCreate();
        await WatchDenchiServerServices.api.registerBattery(
          BatteryCreateRequest(
            type: newEntry.type,
            manufacturer: newEntry.manufacturer,
            quantity: newEntry.quantity,
            storageLocation: newEntry.location,
            chemical: newEntry.chemistry,
          ),
        );
        // POSTが成功した後だけ再取得。タイムアウト時の自動再送はしない。
        final refreshed = await LocalBatteryStore.readInventory();
        if (!mounted) return;
        setState(() => entries = refreshed);
      } catch (error) {
        if (!mounted) return;
        await showError(context,
          'サーバー登録・一覧の更新を確認できませんでした。二重登録防止のため、再登録前にサーバー在庫を確認してください。\n$error');
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
        id: old.id,
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
      await showError(context, '保管場所変更APIはGo側で未実装です。サーバー試験モードでは変更できません');
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
        id: entry.id,
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
        id: old.id,
        type: old.type,
        manufacturer: old.manufacturer,
        quantity: old.quantity + request.quantity,
        location: old.location,
        chemistry: old.chemistry,
      );
    } else {
      updated.add(BatteryEntry(
        id: entry.id,
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
      await showError(context, '機器登録・使用開始APIはGo側で未実装です。サーバー試験モードでは使用できません');
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
        id: entry.id,
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
      // 右上の追加ボタンは撤去。画面右下にスクロールしない固定ボタンを配置。
      navigationBar: const CupertinoNavigationBar(
        backgroundColor: cream,
        border: null,
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
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
                                const Text('右下の＋から電池を追加',
                                    style: TextStyle(color: mutedInk)),
                                const SizedBox(height: 18),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          // 固定された＋ボタンが最後の棚を隠さないように下部を確保。
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 116),
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
            // StackはListViewの外側。スクロールしてもこのボタンは動かない。
            // 下部の3タブより上、右寄りの位置に固定する。
            if (!loading)
              Positioned(
                right: 22,
                bottom: 18,
                child: Semantics(
                  label: '電池を追加',
                  button: true,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: openAddPage,
                    child: Container(
                      width: 68,
                      height: 68,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: coral,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x37B55C55),
                            blurRadius: 15,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(
                        CupertinoIcons.add,
                        size: 35,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
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
  });
  final String deviceName;
  final int quantity;
  final String iconKey;
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
  int count = 1;
  String? iconKey; // 未選択
  String? error;

  @override
  void dispose() {
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
                placeholder: '例：テレビのリモコン、壁掛け時計',
                padding: const EdgeInsets.all(15),
                decoration: inputDecoration(),
                onChanged: (_) {
                  if (error != null) setState(() => error = null);
                },
              ),
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
                      if (option.key != 'other')
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

// ---- 電池の捨て方：日めくりカレンダーUI ----
/// 採用デザイン（2026-11）：月を日付の上に置き、日付を大きく見せる。
/// 地域の自動取得にはまだ接続しない。既存の手動登録データのみ表示する。
/// 端末の幅に合わせて縮むので、小さな画面でも数字がはみ出さない。
class PickupTearOffCalendar extends StatelessWidget {
  const PickupTearOffCalendar({
    super.key,
    required this.date,
    required this.batteryType,
    required this.onEdit,
  });

  final DateTime? date;
  final String batteryType;
  final VoidCallback onEdit;

  static const Color _brown = Color(0xFF684A3D);
  static const Color _red = Color(0xFFE45D51);
  static const Color _sheetColor = Color(0xFFFFFBF7);
  static const Color _dividerColor = Color(0xFFE2C7AD);

  int? get _daysUntil {
    if (date == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date!.year, date!.month, date!.day);
    return target.difference(today).inDays;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // デザイン画像の縦横比を参考にしつつ、実機では可変レイアウトにする。
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 340.0;
        final scale = (width / 340).clamp(0.78, 1.12).toDouble();
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CalendarRing(scale: scale),
                SizedBox(width: 126 * scale),
                _CalendarRing(scale: scale),
              ],
            ),
            Transform.translate(
              offset: Offset(0, -8 * scale),
              child: Stack(
                children: [
                  // 下の紙：めくれる紙の厚みと影。
                  Positioned.fill(
                    top: 10 * scale,
                    left: 10 * scale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8D7C4),
                        borderRadius: BorderRadius.circular(24 * scale),
                        border: Border.all(
                          color: const Color(0xFFDDC7B3),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      right: 10 * scale,
                      bottom: 10 * scale,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 430),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, -0.10),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _calendarSheet(
                        key: ValueKey<String>(
                          '$batteryType-${date?.millisecondsSinceEpoch ?? 0}',
                        ),
                        scale: scale,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _calendarSheet({required Key key, required double scale}) {
    final day = date;
    final remaining = _daysUntil;
    final weekday = day == null
        ? ''
        : const ['日', '月', '火', '水', '木', '金', '土'][day.weekday % 7];

    final String countdown;
    if (remaining == null) {
      countdown = '回収日を設定しよう';
    } else if (remaining < 0) {
      countdown = '予定日を更新してね';
    } else if (remaining == 0) {
      countdown = '今日が回収予定日！';
    } else {
      countdown = 'あと $remaining 日';
    }

    return Container(
      key: key,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        17 * scale, 17 * scale, 17 * scale, 15 * scale,
      ),
      decoration: BoxDecoration(
        color: _sheetColor,
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(color: const Color(0xFFE7D0BC), width: 1.3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1658473D),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 小さな英字見出しと両側の線。
          Row(
            children: [
              const Expanded(child: _CalendarShortRule()),
              SizedBox(width: 9 * scale),
              Icon(
                CupertinoIcons.calendar,
                color: _brown,
                size: 13 * scale,
              ),
              SizedBox(width: 6 * scale),
              Text(
                'NEXT COLLECTION',
                style: TextStyle(
                  color: _brown,
                  fontSize: 10.5 * scale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5 * scale,
                ),
              ),
              SizedBox(width: 9 * scale),
              const Expanded(child: _CalendarShortRule()),
            ],
          ),
          SizedBox(height: 16 * scale),
          Text(
            '$batteryTypeの次の回収予定日',
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17 * scale,
              fontWeight: FontWeight.w800,
              color: _brown,
            ),
          ),
          SizedBox(height: 12 * scale),
          const _DottedRule(),
          if (day == null) ...[
            SizedBox(height: 39 * scale),
            Icon(
              CupertinoIcons.calendar,
              color: const Color(0xFFCBA99A),
              size: 60 * scale,
            ),
            SizedBox(height: 19 * scale),
            Text(
              '回収日はまだ未設定',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _brown,
                fontSize: 18 * scale,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 49 * scale),
          ] else ...[
            SizedBox(height: 20 * scale),
            Text(
              '${day.month}月',
              style: TextStyle(
                color: _brown,
                fontSize: 34 * scale,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
            // 日付が主役。1桁の日付も自然に大きく表示する。
            SizedBox(height: 7 * scale),
            Semantics(
              label: '${day.year}年${day.month}月${day.day}日',
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${day.day}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _red,
                    fontSize: (day.day < 10 ? 143 : 139) * scale,
                    fontWeight: FontWeight.w800,
                    height: 1.02,
                    letterSpacing: -4 * scale,
                  ),
                ),
              ),
            ),
            Text(
              '$weekday曜日',
              style: TextStyle(
                color: _brown,
                fontSize: 24 * scale,
                height: 1.04,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 18 * scale),
          ],
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 25 * scale,
              vertical: 8 * scale,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF9DEDA),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(
              countdown,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _red,
                fontWeight: FontWeight.w800,
                fontSize: 19 * scale,
              ),
            ),
          ),
          SizedBox(height: 17 * scale),
          CupertinoButton(
            onPressed: onEdit,
            padding: EdgeInsets.symmetric(
              horizontal: 7 * scale,
              vertical: 3 * scale,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.pencil, color: _red, size: 17 * scale),
                SizedBox(width: 8 * scale),
                Text(
                  day == null ? '日付を設定する' : '予定日を変更する',
                  style: TextStyle(
                    color: _red,
                    fontSize: 15 * scale,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DottedRule extends StatelessWidget {
  const _DottedRule();

  @override
  Widget build(BuildContext context) => Row(
    children: List.generate(
      23,
      (_) => const Expanded(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: ColoredBox(
            color: PickupTearOffCalendar._dividerColor,
            child: SizedBox(height: 1.8),
          ),
        ),
      ),
    ),
  );
}

class _CalendarShortRule extends StatelessWidget {
  const _CalendarShortRule();

  @override
  Widget build(BuildContext context) => Container(
    height: 1.5,
    color: const Color(0xFFE2C7AD),
  );
}

class _CalendarRing extends StatelessWidget {
  const _CalendarRing({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) => Container(
    width: 16 * scale,
    height: 32 * scale,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10 * scale),
      border: Border.all(
        color: const Color(0xFFA77D5D),
        width: 4 * scale,
      ),
      color: const Color(0xFFF5EFE5),
    ),
  );
}
