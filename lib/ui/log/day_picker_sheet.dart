import 'package:flutter/material.dart';

import '../../domain/day_entry.dart';
import '../../domain/day_kind.dart';
import '../../domain/month_summary.dart';
import '../../domain/vacations.dart';
import '../components/haptics.dart';
import '../components/month_decor.dart';
import '../components/month_picker.dart';
import '../components/mosaic.dart';
import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Alto de cada baldosa del calendario: con el hueco de alrededor, cada día
/// se toca en al menos 48 × 48 px.
const _tileHeight = 46.0;

const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Calendario de «Otro día» en estilo Mosaico, con las horas de cada día
/// (RF-3, RF-28, RF-29). Devuelve el día tocado, o nulo si se cierra.
Future<DateTime?> showDayPickerSheet(
  BuildContext context, {
  required DateTime selected,
  required DateTime today,
  required DateTime firstMonth,
  required Future<List<DayEntry>?> Function(int year, int month) loadMonth,
  VacationDay? Function(DateTime date)? vacationOn,
  bool Function(DateTime date)? isDayOff,
}) => showModalBottomSheet<DateTime>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _DayPickerSheet(
    selected: selected,
    today: today,
    firstMonth: firstMonth,
    loadMonth: loadMonth,
    vacationOn: vacationOn,
    isDayOff: isDayOff,
  ),
);

class _DayPickerSheet extends StatefulWidget {
  const _DayPickerSheet({
    required this.selected,
    required this.today,
    required this.firstMonth,
    required this.loadMonth,
    this.vacationOn,
    this.isDayOff,
  });

  /// Los días de vacaciones sin horas salen en su color, y los medios días
  /// pintados a medias (010, RF-17; 013, RF-12).
  final VacationDay? Function(DateTime date)? vacationOn;

  /// Sábados, domingos y festivos: contorno coral si no tienen horas
  /// (013, RF-6).
  final bool Function(DateTime date)? isDayOff;

  final DateTime selected;
  final DateTime today;
  final DateTime firstMonth;
  final Future<List<DayEntry>?> Function(int year, int month) loadMonth;

  @override
  State<_DayPickerSheet> createState() => _DayPickerSheetState();
}

class _DayPickerSheetState extends State<_DayPickerSheet> {
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);
  List<DayEntry>? _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final month = _month;
    setState(() => _loading = true);
    final entries = await widget.loadMonth(month.year, month.month);
    if (!mounted || month != _month) return; // ya se cambió de mes
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  bool get _canGoBack => _month.isAfter(widget.firstMonth);
  bool get _canGoForward =>
      _month.isBefore(DateTime(widget.today.year, widget.today.month));

  void _go(int delta) {
    Haptics.select();
    _month = DateTime(_month.year, _month.month + delta);
    _load();
  }

  /// Saltar a cualquier mes elegible, como en Vacaciones (012, RF-1).
  Future<void> _pickMonth() async {
    final picked = await showMonthPicker(
      context,
      initial: _month,
      first: widget.firstMonth,
      last: DateTime(widget.today.year, widget.today.month),
    );
    if (picked == null || !mounted || picked == _month) return;
    _month = picked;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entries = _entries ?? const <DayEntry>[];
    final byDay = {for (final e in entries) e.date.day: e};
    final total = MonthSummary.of(
      entries,
      year: _month.year,
      month: _month.month,
    ).totalMinutes;
    final lastDay = DateTime(_month.year, _month.month + 1, 0).day;
    final days = [
      for (var d = 1; d <= lastDay; d++)
        _mosaicDay(DateTime(_month.year, _month.month, d), byDay[d]),
    ];
    final title = '${_months[_month.month - 1]} de ${_month.year}';

    return SafeArea(
      child: Padding(
        // Poco margen a los lados: así cada columna mide al menos 48 px
        // incluso en un móvil de 360 px.
        padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
              child: Text('Elige el día', style: AppText.title),
            ),
            const SizedBox(height: Space.s),
            Row(
              children: [
                IconButton(
                  tooltip: 'Mes anterior',
                  onPressed: _canGoBack ? () => _go(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: TextButton.icon(
                      key: const ValueKey('elegir-mes'),
                      onPressed: _pickMonth,
                      icon: const Icon(Icons.expand_more),
                      iconAlignment: IconAlignment.end,
                      label: DecoratedMonthTitle(
                        year: _month.year,
                        month: _month.month,
                        title: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    title[0].toUpperCase() + title.substring(1),
                                style: AppText.bodyStrong,
                              ),
                              if (!_loading && _entries != null)
                                TextSpan(
                                  text: ' · ${formatMinutes(total)} h',
                                  style: AppText.body.copyWith(
                                    color: c.textSoft,
                                  ),
                                ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.text),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Mes siguiente',
                  onPressed: _canGoForward ? () => _go(1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: Space.s),
            Mosaic(
              key: ValueKey(_month),
              days: days,
              selected: widget.selected,
              today: widget.today,
              showLegend: false,
              tileHeight: _tileHeight,
              markOf: dayMarksOf(context),
              onTap: (date) {
                Haptics.select();
                Navigator.of(context).pop(date);
              },
            ),
            if (!_loading && _entries == null)
              Padding(
                padding: const EdgeInsets.all(Space.m),
                child: Text(
                  'No se han podido leer las horas de este mes.',
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(color: c.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  MosaicDay _mosaicDay(DateTime date, DayEntry? entry) {
    if (entry == null) {
      final vacation = widget.vacationOn?.call(date);
      if (vacation != null) {
        return vacation.half
            ? MosaicDay.half(date, DataKind.vacation, '½')
            : MosaicDay(date, DataKind.vacation);
      }
      return widget.isDayOff?.call(date) ?? false
          ? MosaicDay.muted(date)
          : MosaicDay(date);
    }
    return MosaicDay(
      date,
      entry.kind == DayKind.festive ? DataKind.festive : DataKind.normal,
      formatMinutes(entry.minutes),
      hoursPhrase(entry.minutes),
    );
  }
}
