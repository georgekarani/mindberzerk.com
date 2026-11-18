import 'package:flutter_test/flutter_test.dart';
import 'package:g_launcher/data/prefs/desklet_layout.dart';
import 'package:g_launcher/data/prefs/launcher_prefs.dart';

/// PHASE 3c. Groups, align and distribute, all pure, all-or-nothing.
///
/// Every refusal is asserted by IDENTITY, because that is the signal the
/// editor reads: the same object back means nothing moved.
const cols = 20;
const rows = 20;

Desklet _d(String id, int col, int row,
        {int w = 2, int h = 2, int page = 0, String? group}) =>
    Desklet(
      id: id,
      kind: 'clock',
      page: page,
      col: col,
      row: row,
      spanX: w,
      spanY: h,
      group: group,
    );

LauncherPrefs _with(List<Desklet> ds) => LauncherPrefs(desklets: ds);

Desklet _get(LauncherPrefs p, String id) => DeskletLayout.byId(p, id)!;

void main() {
  group('json', () {
    test('group round-trips and is omitted when null', () {
      final d = _d('a', 0, 0, group: 'g1');
      expect(Desklet.fromJson(d.toJson()), d);
      expect(_d('b', 0, 0).toJson().containsKey('group'), isFalse);
    });
  });

  group('groupOf', () {
    test('an ungrouped tile is its own group', () {
      final p = _with([_d('a', 0, 0)]);
      expect(DeskletLayout.groupOf(p, 'a'), {'a'});
    });

    test('members on another page are left out', () {
      final p = _with([
        _d('a', 0, 0, group: 'g'),
        _d('b', 4, 0, group: 'g'),
        _d('c', 0, 0, group: 'g', page: -1),
      ]);
      expect(DeskletLayout.groupOf(p, 'a'), {'a', 'b'});
    });
  });

  group('placeMany', () {
    test('two tiles can swap places in one write', () {
      final p = _with([_d('a', 0, 0), _d('b', 4, 0)]);
      final out = DeskletLayout.placeMany(
        p,
        {'a': (col: 4, row: 0), 'b': (col: 0, row: 0)},
        cols: cols,
        rows: rows,
      );
      expect(_get(out, 'a').col, 4);
      expect(_get(out, 'b').col, 0);
    });

    test('one target off the grid refuses the lot', () {
      final p = _with([_d('a', 0, 0), _d('b', 4, 0)]);
      final out = DeskletLayout.placeMany(
        p,
        {'a': (col: 2, row: 0), 'b': (col: 19, row: 0)},
        cols: cols,
        rows: rows,
      );
      expect(identical(out, p), isTrue);
    });

    test('landing on a tile outside the set is refused', () {
      final p = _with([_d('a', 0, 0), _d('x', 6, 0)]);
      final out = DeskletLayout.placeMany(
        p,
        {'a': (col: 6, row: 1)},
        cols: cols,
        rows: rows,
      );
      expect(identical(out, p), isTrue);
    });

    test('no change returns the same object', () {
      final p = _with([_d('a', 0, 0)]);
      final out = DeskletLayout.placeMany(
        p,
        {'a': (col: 0, row: 0)},
        cols: cols,
        rows: rows,
      );
      expect(identical(out, p), isTrue);
    });
  });

  group('moveGroup', () {
    test('every member moves by the same offset', () {
      final p = _with([
        _d('a', 0, 0, group: 'g'),
        _d('b', 3, 1, group: 'g'),
        _d('x', 10, 10),
      ]);
      final out = DeskletLayout.moveGroup(p,
          id: 'b', dCol: 2, dRow: 3, cols: cols, rows: rows);
      expect((_get(out, 'a').col, _get(out, 'a').row), (2, 3));
      expect((_get(out, 'b').col, _get(out, 'b').row), (5, 4));
      expect(_get(out, 'x').col, 10);
    });

    test('a member hitting the edge holds the whole group back', () {
      final p = _with([
        _d('a', 0, 0, group: 'g'),
        _d('b', 17, 0, group: 'g'),
      ]);
      final out = DeskletLayout.moveGroup(p,
          id: 'a', dCol: 2, dRow: 0, cols: cols, rows: rows);
      expect(identical(out, p), isTrue);
    });
  });

  group('group and ungroup', () {
    test('one tile is not a group', () {
      final p = _with([_d('a', 0, 0), _d('b', 4, 0)]);
      expect(
        identical(DeskletLayout.group(p, {'a'}, groupId: 'g'), p),
        isTrue,
      );
    });

    test('grouping two tiles tags both', () {
      final p = _with([_d('a', 0, 0), _d('b', 4, 0)]);
      final out = DeskletLayout.group(p, {'a', 'b'}, groupId: 'g');
      expect(_get(out, 'a').group, 'g');
      expect(_get(out, 'b').group, 'g');
    });

    test('a group left with one member dissolves', () {
      final p = _with([
        _d('a', 0, 0, group: 'old'),
        _d('b', 4, 0, group: 'old'),
        _d('c', 8, 0),
      ]);
      final out = DeskletLayout.group(p, {'a', 'c'}, groupId: 'new');
      expect(_get(out, 'a').group, 'new');
      expect(_get(out, 'c').group, 'new');
      expect(_get(out, 'b').group, isNull);
    });

    test('ungrouping one of two clears both', () {
      final p = _with([
        _d('a', 0, 0, group: 'g'),
        _d('b', 4, 0, group: 'g'),
      ]);
      final out = DeskletLayout.ungroup(p, {'a'});
      expect(_get(out, 'a').group, isNull);
      expect(_get(out, 'b').group, isNull);
    });

    test('ungrouping tiles with no group changes nothing', () {
      final p = _with([_d('a', 0, 0)]);
      expect(identical(DeskletLayout.ungroup(p, {'a'}), p), isTrue);
    });
  });

  group('align', () {
    final p = _with([
      _d('a', 1, 0, w: 2),
      _d('b', 5, 4, w: 4),
      _d('c', 3, 8, w: 2),
    ]);

    test('left edges meet at the leftmost', () {
      final out = DeskletLayout.align(p, {'a', 'b', 'c'}, DeskletAlign.left,
          cols: cols, rows: rows);
      expect([for (final id in 'abc'.split('')) _get(out, id).col], [1, 1, 1]);
    });

    test('right edges meet at the rightmost', () {
      final out = DeskletLayout.align(p, {'a', 'b', 'c'}, DeskletAlign.right,
          cols: cols, rows: rows);
      expect([for (final id in 'abc'.split('')) _get(out, id).right],
          [9, 9, 9]);
    });

    test('centres share a column', () {
      final out = DeskletLayout.align(
          p, {'a', 'b', 'c'}, DeskletAlign.centerX,
          cols: cols, rows: rows);
      // Box is 1..9, centre 5: a and c (span 2) at 4, b (span 4) at 3.
      expect([for (final id in 'abc'.split('')) _get(out, id).col], [4, 3, 4]);
    });

    test('aligning onto each other is refused, not half applied', () {
      final q = _with([_d('a', 0, 0), _d('b', 4, 0)]);
      final out = DeskletLayout.align(q, {'a', 'b'}, DeskletAlign.left,
          cols: cols, rows: rows);
      expect(identical(out, q), isTrue);
    });
  });

  group('distribute', () {
    test('equal gaps, ends stay put', () {
      final p = _with([
        _d('a', 0, 0, w: 2),
        _d('b', 3, 3, w: 2),
        _d('c', 12, 6, w: 2),
      ]);
      final out = DeskletLayout.distribute(p, {'a', 'b', 'c'},
          horizontal: true, cols: cols, rows: rows);
      // Inner run 2..12 holds b (2) and two gaps of 4.
      expect(_get(out, 'a').col, 0);
      expect(_get(out, 'b').col, 6);
      expect(_get(out, 'c').col, 12);
    });

    test('two tiles have nothing to space', () {
      final p = _with([_d('a', 0, 0), _d('b', 8, 0)]);
      expect(
        identical(
          DeskletLayout.distribute(p, {'a', 'b'},
              horizontal: true, cols: cols, rows: rows),
          p,
        ),
        isTrue,
      );
    });
  });
}
