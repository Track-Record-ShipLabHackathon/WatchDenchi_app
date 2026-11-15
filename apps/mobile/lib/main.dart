import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api_config.dart';

// WatchDenchi / Flutterだけで動く試作版。
// 保存先は端末内。Go APIとの通信はまだ行いません。
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

void main() {
  if (kDebugMode) {
    debugPrint('WatchDenchi API: $watchDenchiApiBaseUrl');
  }
  runApp(const BatteryApp());
}

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
      home: HomePage(),
    );
  }
}

// 旧バージョンの保存データも読み込めるように、既存フィールド名を維持。
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
        // 旧データは電池の中身が未登録。アルカリと決めつけない。
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
  });

  final String deviceName;
  final String type;
  final String manufacturer;
  final int quantity;
  final DateTime startedAt;

  Map<String, dynamic> toJson() => {
        'deviceName': deviceName,
        'type': type,
        'manufacturer': manufacturer,
        'quantity': quantity,
        'startedAt': startedAt.toIso8601String(),
      };

  factory DeviceUsage.fromJson(Map<String, dynamic> json) => DeviceUsage(
        deviceName: json['deviceName'] as String? ?? '名前のない機器',
        type: json['type'] as String? ?? 'その他',
        manufacturer: json['manufacturer'] as String? ?? '不明',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

// 同じ端末内で、在庫と使用中の機器を別々に保存する。
class LocalBatteryStore {
  LocalBatteryStore._();

  static final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const String inventoryKey = 'battery_inventory_v2';
  static const String olderInventoryKey = 'battery_inventory_v1';
  static const String deviceKey = 'watchdenchi_device_usage_v1';

  static Future<List<BatteryEntry>> readInventory() async {
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
}

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

// アップロードされたイラストのような、やわらかい平面タッチの電池。
// ロゴや実際の商品パッケージをそのまま再現するものではありません。
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

class _SoftBatteryPainter extends CustomPainter {
  const _SoftBatteryPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 76);
    final paint = Paint()..isAntiAlias = true;

    // 底と金属キャップ。
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

    // 白い電池本体と色付きの上部。
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 9, 34, 62), const Radius.circular(4)));
    paint.color = const Color(0xFFFAF9F3);
    canvas.drawRect(const Rect.fromLTWH(3, 9, 34, 62), paint);
    paint.color = accent;
    canvas.drawRect(const Rect.fromLTWH(3, 10, 34, 29), paint);

    // 端にほんの少しだけ濃淡をつけて、紙のイラストらしくする。
    paint.color = const Color(0x16000000);
    canvas.drawRect(const Rect.fromLTWH(30, 10, 7, 61), paint);
    paint.color = const Color(0x16FFFFFF);
    canvas.drawRect(const Rect.fromLTWH(7, 10, 6, 61), paint);

    // ＋ と − 。参照画像の特徴的な見た目。
    paint.color = const Color(0xFFFCFAF6);
    canvas.drawRect(const Rect.fromLTWH(18, 16, 5, 16), paint);
    canvas.drawRect(const Rect.fromLTWH(12.5, 21.5, 16, 5), paint);
    paint.color = const Color(0xFF80716A);
    canvas.drawRect(const Rect.fromLTWH(14, 61, 12, 3.5), paint);
    canvas.restore();

    // 縁のグレーの細いバンドと、底の丸み。
    paint.color = const Color(0x559B908A);
    canvas.drawRect(const Rect.fromLTWH(3, 9, 34, 2), paint);
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
      CupertinoPageRoute<void>(builder: (_) => const InventoryPage()),
    );
    if (!mounted) return;
    await loadHome();
  }

  Future<void> finishUsage(DeviceUsage usage) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('使用を終了しますか？'),
        content: Text('${usage.deviceName}で使っている${usage.quantity}本を使用中一覧から外します。\n在庫には戻しません。'),
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
    final updated = [...devices]..remove(usage);
    try {
      await LocalBatteryStore.saveDevices(updated);
      if (!mounted) return;
      setState(() => devices = updated);
    } catch (error) {
      if (!mounted) return;
      await showError(context, '使用情報を保存できませんでした。\n$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final stockCount = inventory.fold<int>(0, (sum, item) => sum + item.quantity);
    final usingCount = devices.fold<int>(0, (sum, item) => sum + item.quantity);
    final deviceCount = devices.map((e) => e.deviceName).toSet().length;

    return CupertinoPageScaffold(
      backgroundColor: cream,
      navigationBar: const CupertinoNavigationBar(
        backgroundColor: cream,
        border: null,
        middle: Text('WatchDenchi', style: TextStyle(color: ink)),
      ),
      child: SafeArea(
        child: loading
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
                children: [

                  // 在庫棚をそのまま開ける大きなボタン。
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: openInventory,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: softCardDecoration(),
                      child: Row(
                        children: [
                          Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1E1D0),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SoftBattery(manufacturer: 'maxell', size: 51),
                                  SizedBox(width: 1),
                                  SoftBattery(manufacturer: 'Panasonic', size: 51),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('在庫棚',
                                    style: TextStyle(
                                      color: ink,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                    )),
                                const SizedBox(height: 5),
                                Text('ストック：$stockCount 本',
                                    style: const TextStyle(
                                        color: mutedInk, fontSize: 14)),
                              ],
                            ),
                          ),
                          const Icon(CupertinoIcons.chevron_right,
                              size: 18, color: mutedInk),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Text('いま使っている電池',
                      style: TextStyle(color: ink, fontSize: 20,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _CountPill(label: '機器', value: '$deviceCount 台'),
                      const SizedBox(width: 9),
                      _CountPill(label: '使用中', value: '$usingCount 本'),
                    ],
                  ),
                  const SizedBox(height: 13),
                  if (devices.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 25),
                      decoration: softCardDecoration(),
                      child: const Column(
                        children: [
                          Icon(CupertinoIcons.house_alt,
                              color: Color(0xFFC09A7D), size: 30),
                          SizedBox(height: 10),
                          Text('まだ使用中の電池はありません',
                              style: TextStyle(
                                  color: ink, fontWeight: FontWeight.w600)),
                          SizedBox(height: 6),
                          Text('在庫棚の電池をタップして、\n使う機器を登録',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: mutedInk, fontSize: 13)),
                        ],
                      ),
                    )
                  else
                    for (final usage in devices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
                          decoration: softCardDecoration(),
                          child: Row(
                            children: [
                              const Icon(CupertinoIcons.house_fill,
                                  color: Color(0xFFC69A82), size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(usage.deviceName,
                                        style: const TextStyle(
                                            color: ink, fontSize: 16,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 3),
                                    Text('${usage.type}・${usage.quantity}本・${usage.manufacturer}',
                                        style: const TextStyle(
                                            color: mutedInk, fontSize: 12)),
                                    const SizedBox(height: 3),
                                    Text(_elapsedLabel(usage.startedAt),
                                        style: const TextStyle(
                                            color: mutedInk, fontSize: 12)),
                                  ],
                                ),
                              ),
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                onPressed: () => finishUsage(usage),
                                child: const Text('使用終了',
                                    style: TextStyle(
                                        color: coral, fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 11),
                  const Text('※ 使用本数と開始日を記録しています。電池の残寿命の予測は今後追加予定です。',
                      style: TextStyle(color: mutedInk, fontSize: 11)),
                ],
              ),
      ),
    );
  }

  String _elapsedLabel(DateTime start) {
    final days = DateTime.now().difference(start).inDays;
    if (days <= 0) return '今日から使用';
    return '使い始めて $days 日';
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: paleCoral,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text('$label  $value',
            style: const TextStyle(
                color: ink, fontSize: 13, fontWeight: FontWeight.w600)),
      );
}

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
      await showError(context, '在庫の読み込みに失敗しました。\n$error');
    }
  }

  Future<void> openAddPage() async {
    final newEntry = await Navigator.of(context).push<BatteryEntry>(
      CupertinoPageRoute<BatteryEntry>(builder: (_) => const AddBatteryPage()),
    );
    if (!mounted || newEntry == null) return;

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
      await showError(context, '登録を保存できませんでした。\n$error');
    }
  }

  Future<void> useBattery(BatteryEntry entry) async {
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
      ),
    ];

    try {
      // 両方の保存が成功したら画面を更新する。
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
          '保存に失敗しました。通信ではなく端末保存のエラーです。\n$error');
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
        middle: const Text('わたしの在庫棚', style: TextStyle(color: ink)),
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
                          const Text('棚はまだ空っぽです',
                              style: TextStyle(
                                  color: ink, fontSize: 19,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          const Text('右上の＋から電池を並べてみよう。',
                              style: TextStyle(color: mutedInk)),
                          const SizedBox(height: 18),
                          CupertinoButton.filled(
                            onPressed: openAddPage,
                            child: const Text('電池を追加'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
                    children: [
                      const SizedBox(height: 18),
                      for (final type in groupedTypes)
                        _ShelfSection(
                          title: type,
                          entries: entries.where((e) => e.type == type).toList(),
                          onUse: useBattery,
                        ),
                    ],
                  ),
      ),
    );
  }
}

// 背面板と木の棚板。電池が実際に棚に載っているように見せる。
class _ShelfSection extends StatelessWidget {
  const _ShelfSection({
    required this.title,
    required this.entries,
    required this.onUse,
  });

  final String title;
  final List<BatteryEntry> entries;
  final ValueChanged<BatteryEntry> onUse;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 15, 14, 15),
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: paper,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(title, style: const TextStyle(
                      color: ink, fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                Text('${entries.fold<int>(0, (n, e) => n + e.quantity)}本',
                    style: const TextStyle(color: mutedInk, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            for (final entry in entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(5, 8, 5, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.manufacturer, style: const TextStyle(
                        color: ink, fontSize: 16,
                        fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text([
                      if (entry.chemistry.isNotEmpty) entry.chemistry,
                      if (entry.location.isNotEmpty) entry.location,
                    ].join(' ・ '), style: const TextStyle(
                        color: mutedInk, fontSize: 12)),
                    const SizedBox(height: 10),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 4,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < entry.quantity && i < 5; i++)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onUse(entry),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: SoftBattery(
                                manufacturer: entry.manufacturer,
                                size: 73,
                              ),
                            ),
                          ),
                        if (entry.quantity > 5)
                          GestureDetector(
                            onTap: () => onUse(entry),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 5, left: 6),
                              width: 44,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: paper.withAlpha(195),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text('+${entry.quantity - 5}',
                                  style: const TextStyle(color: ink,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                height: 15,
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
              const SizedBox(height: 15),
            ],
          ],
        ),
      ),
    );
  }
}

class UseBatteryRequest {
  const UseBatteryRequest({required this.deviceName, required this.quantity});
  final String deviceName;
  final int quantity;
}

class UseBatterySheet extends StatefulWidget {
  const UseBatterySheet({super.key, required this.entry});
  final BatteryEntry entry;

  @override
  State<UseBatterySheet> createState() => _UseBatterySheetState();
}

class _UseBatterySheetState extends State<UseBatterySheet> {
  final TextEditingController deviceController = TextEditingController();
  int count = 1;
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
    Navigator.of(context).pop(
      UseBatteryRequest(deviceName: name, quantity: count),
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
              const Text('どこで使う？',
                  style: TextStyle(color: ink, fontSize: 23,
                      fontWeight: FontWeight.w700)),
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
                    child: Text('$count 本',
                        style: const TextStyle(color: ink, fontSize: 20,
                            fontWeight: FontWeight.w700)),
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
      await showError(context, 'メーカー名を入力してね。');
      return;
    }
    if (quantity == null || quantity <= 0) {
      await showError(context, '本数は1以上の整数を入力してね。');
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
            const Text('電池を棚にならべよう',
                textAlign: TextAlign.center,
                style: TextStyle(color: ink, fontSize: 21,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
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

Future<void> showError(BuildContext context, String message) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('確認してね'),
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
