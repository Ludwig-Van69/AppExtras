import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Hoja con el año (flechas) y los 12 meses para saltar a cualquier mes entre
/// [first] y [last]. La usan Vacaciones (011, RF-1) y el calendario de «Otro
/// día» (012, RF-1). Devuelve el primer día del mes elegido, o nulo.
Future<DateTime?> showMonthPicker(
  BuildContext context, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
}) => showModalBottomSheet<DateTime>(
  context: context,
  showDragHandle: true,
  builder: (_) => _MonthPicker(initial: initial, first: first, last: last),
);

class _MonthPicker extends StatefulWidget {
  const _MonthPicker({
    required this.initial,
    required this.first,
    required this.last,
  });

  final DateTime initial;
  final DateTime first;
  final DateTime last;

  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late int _year = widget.initial.year;

  bool _allowed(int month) {
    final m = DateTime(_year, month);
    return !m.isBefore(DateTime(widget.first.year, widget.first.month)) &&
        !m.isAfter(DateTime(widget.last.year, widget.last.month));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Año anterior',
                  onPressed: _year > widget.first.year
                      ? () => setState(() => _year--)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '$_year',
                    textAlign: TextAlign.center,
                    style: AppText.title,
                  ),
                ),
                IconButton(
                  tooltip: 'Año siguiente',
                  onPressed: _year < widget.last.year
                      ? () => setState(() => _year++)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: Space.s),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.4,
              mainAxisSpacing: Space.s,
              crossAxisSpacing: Space.s,
              children: [
                for (var m = 1; m <= 12; m++)
                  _allowed(m) &&
                          m == widget.initial.month &&
                          _year == widget.initial.year
                      ? FilledButton(
                          onPressed: () =>
                              Navigator.of(context).pop(DateTime(_year, m)),
                          child: _monthLabel(m),
                        )
                      : OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.text,
                          ),
                          onPressed: _allowed(m)
                              ? () =>
                                    Navigator.of(context)
                                        .pop(DateTime(_year, m))
                              : null,
                          child: _monthLabel(m),
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthLabel(int m) {
    final name = monthName(m);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(name[0].toUpperCase() + name.substring(1)),
    );
  }
}
