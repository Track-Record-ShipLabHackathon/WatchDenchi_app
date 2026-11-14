import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 電池の種類。必要になったら、ここに種類を追加できます。
const List<String> batteryTypes = [
  '単1形',
  '単2形',
  '単3形',
  '単4形',
  '単5形',
  '9V形',
  'CR2032',
  'CR2025',
  'LR44',
  'その他',
];

void main() {
  runApp(const BatteryApp());
}

class BatteryApp extends StatelessWidget {
  const BatteryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: CupertinoThemeData(brightness: Brightness.dark),
      home: HomePage(),
    );
  }
}

// 登録する電池1種類分のデータです。
class BatteryEntry {
  const BatteryEntry({
    required this.type,
    required this.manufacturer,
    required this.quantity,
    required this.location,
  });

  final String type;
  final String manufacturer;
  final int quantity;
  final String location;

  Map<String, dynamic> toJson() => {
        'type': type,
        'manufacturer': manufacturer,
        'quantity': quantity,
        'location': location,
      };

  factory BatteryEntry.fromJson(Map<String, dynamic> json) => BatteryEntry(
        type: json['type'] as String? ?? 'その他',
        manufacturer: json['manufacturer'] as String? ?? '不明',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        location: json['location'] as String? ?? '',
      );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('電池管理アプリ'),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topLeft,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (context) => const InventoryPage(),
                  ),
                );
              },
              child: Container(
                height: 140,
                width: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: CupertinoColors.white, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    '🔋\n在庫棚',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 22,
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

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  static const String storageKey = 'battery_inventory_v1';
  final SharedPreferencesAsync preferences = SharedPreferencesAsync();
  List<BatteryEntry> entries = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadEntries();
  }

  Future<void> loadEntries() async {
    var loaded = <BatteryEntry>[];
    try {
      final saved = await preferences.getString(storageKey);
      if (saved != null) {
        final decoded = jsonDecode(saved) as List<dynamic>;
        loaded = decoded
            .map((value) =>
                BatteryEntry.fromJson(Map<String, dynamic>.from(value as Map)))
            .toList();
      }
    } catch (error) {
      // 保存内容を読み込めなかったときは空の一覧で始めます。
      debugPrint('在庫の読み込みに失敗: $error');
    }
    if (!mounted) return;
    setState(() {
      entries = loaded;
      loading = false;
    });
  }

  Future<void> saveEntries() async {
    try {
      final encoded = jsonEncode(entries.map((entry) => entry.toJson()).toList());
      await preferences.setString(storageKey, encoded);
    } catch (error) {
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('保存できませんでした'),
          content: Text('端末への保存に失敗しました: $error'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
  }

  Future<void> openAddPage() async {
    final newEntry = await Navigator.of(context).push<BatteryEntry>(
      CupertinoPageRoute<BatteryEntry>(
        builder: (context) => const AddBatteryPage(),
      ),
    );
    if (!mounted || newEntry == null) return;

    // 同じ「種類＋メーカー＋保管場所」なら本数を合算します。
    final index = entries.indexWhere(
      (entry) =>
          entry.type == newEntry.type &&
          entry.manufacturer.toLowerCase() ==
              newEntry.manufacturer.toLowerCase() &&
          entry.location == newEntry.location,
    );
    setState(() {
      if (index == -1) {
        entries.add(newEntry);
      } else {
        final old = entries[index];
        entries[index] = BatteryEntry(
          type: old.type,
          manufacturer: old.manufacturer,
          quantity: old.quantity + newEntry.quantity,
          location: old.location,
        );
      }
    });
    await saveEntries();
  }

  @override
  Widget build(BuildContext context) {
    final groupedTypes = batteryTypes.where(
      (type) => entries.any((entry) => entry.type == type),
    );

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('在庫棚'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: openAddPage,
          child: const Icon(CupertinoIcons.add, size: 26),
        ),
      ),
      child: SafeArea(
        child: loading
            ? const Center(child: CupertinoActivityIndicator())
            : entries.isEmpty
                ? const Center(
                    child: Text('まだ電池は登録されていません。\n右上の＋から追加してみよう！',
                        textAlign: TextAlign.center),
                  )
                : ListView(
                    children: [
                      for (final type in groupedTypes)
                        CupertinoListSection.insetGrouped(
                          header: Text(type),
                          children: [
                            for (final entry in entries.where(
                              (entry) => entry.type == type,
                            ))
                              CupertinoListTile(
                                leading: const Icon(
                                  CupertinoIcons.battery_100,
                                  color: CupertinoColors.systemGreen,
                                ),
                                title: Text(entry.manufacturer),
                                subtitle: entry.location.isEmpty
                                    ? null
                                    : Text('保管場所：${entry.location}'),
                                trailing: Text('${entry.quantity}本'),
                              ),
                          ],
                        ),
                      const SizedBox(height: 30),
                    ],
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
  final TextEditingController manufacturerController = TextEditingController();
  final TextEditingController quantityController =
      TextEditingController(text: '1');
  final TextEditingController locationController = TextEditingController();
  String selectedType = '単3形';

  @override
  void dispose() {
    manufacturerController.dispose();
    quantityController.dispose();
    locationController.dispose();
    super.dispose();
  }

  Future<void> pickType() async {
    final type = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: const Text('電池の種類を選んでね'),
        actions: [
          for (final option in batteryTypes)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(popupContext).pop(option),
              child: Text(option),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('キャンセル'),
        ),
      ),
    );
    if (!mounted || type == null) return;
    setState(() => selectedType = type);
  }

  Future<void> showError(String message) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('入力を確認してね'),
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

  Future<void> submit() async {
    final manufacturer = manufacturerController.text.trim();
    final quantity = int.tryParse(quantityController.text.trim());
    final location = locationController.text.trim();

    if (manufacturer.isEmpty) {
      await showError('メーカーを入力してください。');
      return;
    }
    if (quantity == null || quantity <= 0) {
      await showError('本数には1以上の整数を入力してください。');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      BatteryEntry(
        type: selectedType,
        manufacturer: manufacturer,
        quantity: quantity,
        location: location,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('電池を追加'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('メーカー'),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: manufacturerController,
              placeholder: '例：Panasonic、maxell',
              padding: const EdgeInsets.all(14),
            ),
            const SizedBox(height: 24),
            const Text('電池の種類'),
            const SizedBox(height: 8),
            CupertinoButton(
              color: CupertinoColors.secondarySystemFill,
              onPressed: pickType,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(selectedType),
                  const Icon(CupertinoIcons.chevron_down, size: 16),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('追加する本数'),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: quantityController,
              placeholder: '例：4',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              padding: const EdgeInsets.all(14),
            ),
            const SizedBox(height: 24),
            const Text('保管場所（任意）'),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: locationController,
              placeholder: '例：リビングの引き出し',
              padding: const EdgeInsets.all(14),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: submit,
                child: const Text('在庫に追加する'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
