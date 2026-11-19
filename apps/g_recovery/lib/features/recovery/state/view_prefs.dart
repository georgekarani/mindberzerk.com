import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_groups.dart';
import '../../../core/prefs/prefs_store.dart';

/// How a category's items are sectioned.
enum GroupBy {
  date,
  app,
  size;

  String get label => switch (this) {
    GroupBy.date => 'Date',
    GroupBy.app => 'App',
    GroupBy.size => 'Size',
  };
}

/// Photo grid columns, changed by pinching. Remembered between launches.
class GridColumns extends Notifier<int> {
  static const String _key = 'view.gridColumns';
  static const int min = 2;
  static const int max = 6;

  @override
  int build() =>
      ref.read(prefsStoreProvider).readInt(_key, fallback: 3).clamp(min, max);

  /// One step, in either direction. Returns whether anything changed.
  bool step({required bool fewer}) {
    final int next = (state + (fewer ? -1 : 1)).clamp(min, max);
    if (next == state) return false;
    state = next;
    ref.read(prefsStoreProvider).writeInt(_key, next);
    return true;
  }
}

final NotifierProvider<GridColumns, int> gridColumnsProvider =
    NotifierProvider<GridColumns, int>(GridColumns.new);

/// The chosen sectioning. Remembered between launches.
class GroupByController extends Notifier<GroupBy> {
  static const String _key = 'view.groupBy';

  @override
  GroupBy build() {
    final String? stored = ref.read(prefsStoreProvider).readString(_key);
    return GroupBy.values.firstWhere(
      (GroupBy g) => g.name == stored,
      orElse: () => GroupBy.date,
    );
  }

  void select(GroupBy next) {
    state = next;
    ref.read(prefsStoreProvider).writeString(_key, next.name);
  }
}

final NotifierProvider<GroupByController, GroupBy> groupByProvider =
    NotifierProvider<GroupByController, GroupBy>(GroupByController.new);

/// Groups by the app a file came from, read off its folder path. Largest
/// group first; files with no recognisable folder go last as "Other".
List<DateGroup<T>> groupByApp<T>(
  List<T> items, {
  required String? Function(T) pathOf,
  required int Function(T) sizeOf,
}) {
  final Map<String, List<T>> byApp = <String, List<T>>{};
  final List<T> other = <T>[];
  for (final T item in items) {
    final String? app = appFromPath(pathOf(item));
    if (app == null) {
      other.add(item);
    } else {
      byApp.putIfAbsent(app, () => <T>[]).add(item);
    }
  }
  int sum(List<T> list) => list.fold<int>(0, (int s, T i) => s + sizeOf(i));
  final List<DateGroup<T>> groups = <DateGroup<T>>[
    for (final MapEntry<String, List<T>> e in byApp.entries)
      DateGroup<T>(
        label: e.key,
        items: e.value,
        bytes: sum(e.value),
        dated: true,
      ),
  ]..sort((DateGroup<T> a, DateGroup<T> b) => b.count.compareTo(a.count));
  if (other.isNotEmpty) {
    groups.add(
      DateGroup<T>(
        label: 'Other',
        items: other,
        bytes: sum(other),
        dated: false,
      ),
    );
  }
  return groups;
}

/// A friendly app or folder name for a relative path, or null.
///
/// Known apps are matched by the package or folder name they write to;
/// anything else is named after its top folder, which is usually the app.
String? appFromPath(String? path) {
  if (path == null || path.isEmpty) return null;
  final String p = path.toLowerCase();
  const List<(String, String)> known = <(String, String)>[
    ('whatsapp', 'WhatsApp'),
    ('telegram', 'Telegram'),
    ('instagram', 'Instagram'),
    ('snapchat', 'Snapchat'),
    ('facebook', 'Facebook'),
    ('messenger', 'Messenger'),
    ('tiktok', 'TikTok'),
    ('twitter', 'X'),
    ('screenshots', 'Screenshots'),
    ('screen recordings', 'Screen recordings'),
    ('dcim/camera', 'Camera'),
    ('download', 'Downloads'),
    ('bluetooth', 'Bluetooth'),
  ];
  for (final (String needle, String name) in known) {
    if (p.contains(needle)) return name;
  }
  final List<String> parts = path
      .split('/')
      .where((String s) => s.isNotEmpty && s != 'Android' && s != 'media')
      .toList();
  return parts.isEmpty ? null : parts.first;
}

/// Groups into four size bands, largest band first. Empty bands are left
/// out.
List<DateGroup<T>> groupBySize<T>(
  List<T> items, {
  required int Function(T) sizeOf,
}) {
  const int kb = 1024;
  const int mb = 1024 * 1024;
  final List<(String, bool Function(int))> bands =
      <(String, bool Function(int))>[
        ('Over 10 MB', (int b) => b >= 10 * mb),
        ('1 to 10 MB', (int b) => b >= mb && b < 10 * mb),
        ('100 KB to 1 MB', (int b) => b >= 100 * kb && b < mb),
        ('Under 100 KB', (int b) => b < 100 * kb),
      ];
  return <DateGroup<T>>[
    for (final (String label, bool Function(int) fits) in bands)
      if (items.any((T i) => fits(sizeOf(i))))
        () {
          final List<T> inBand = items.where((T i) => fits(sizeOf(i))).toList()
            ..sort((T a, T b) => sizeOf(b).compareTo(sizeOf(a)));
          return DateGroup<T>(
            label: label,
            items: inBand,
            bytes: inBand.fold<int>(0, (int s, T i) => s + sizeOf(i)),
            dated: true,
          );
        }(),
  ];
}
