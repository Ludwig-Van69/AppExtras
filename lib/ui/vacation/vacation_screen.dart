import 'package:flutter/material.dart';

import '../../domain/vacations.dart';
import '../components/info_button.dart';
import '../components/month_decor.dart';
import '../components/month_picker.dart';
import '../components/mosaic.dart';
import '../components/state_message.dart';
import '../components/undo.dart';
import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'vacation_controller.dart';
import 'vacation_settings_screen.dart';

/// Las dos vistas por año (RF-13 a RF-15).
enum VacationView { ownYear, calendarYear }

String _shortDate(DateTime d) =>
    '${d.day} ${monthName(d.month).substring(0, 3)}';

/// «10,5 días», «1 día».
String daysText(int halfDays) =>
    '${formatHalfDays(halfDays)} ${halfDays == 2 ? 'día' : 'días'}';

/// Sección «Vacaciones» (010, RF-4 a RF-15): lo que queda, el mosaico del mes
/// para marcar días y las dos vistas por año.
class VacationScreen extends StatefulWidget {
  const VacationScreen({
    super.key,
    required this.vacation,
    this.actions = const [],
  });

  final VacationController vacation;

  /// Botones extra de la barra de título (el engranaje de Ajustes).
  final List<Widget> actions;

  @override
  State<VacationScreen> createState() => _VacationScreenState();
}

class _VacationScreenState extends State<VacationScreen> {
  VacationController get _v => widget.vacation;
  late DateTime _month = DateTime(_v.today.year, _v.today.month);
  VacationView _view = VacationView.ownYear;
  UndoHandle? _undo;

  @override
  void dispose() {
    _undo?.dismiss();
    super.dispose();
  }

  void _say(String text) {
    _undo = null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  bool _canGo(int delta) {
    final s = _v.settings;
    if (s == null) return false;
    final (first, last) = vacationRange(s, _v.today);
    final target = DateTime(_month.year, _month.month + delta);
    return !target.isBefore(DateTime(first.year, first.month)) &&
        !target.isAfter(DateTime(last.year, last.month));
  }

  void _go(int delta) {
    if (!_canGo(delta)) return;
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  Future<void> _tap(DateTime date) async {
    _undo?.dismiss();
    final result = await _v.toggle(date);
    if (!mounted) return;
    switch (result) {
      case VacationTap.marked:
        final day = _v.dayOn(date);
        if (day != null && day.countsForPreviousYear) {
          _say('${_shortDate(date)}: cuenta para ${day.year}');
        }
      case VacationTap.unmarked:
        final removed = _v.lastRemoved!;
        _undo = showUndo(
          context,
          message: '${_shortDate(date)} ya no es de vacaciones',
          onUndo: () => _v.restore(removed),
        );
      case VacationTap.notWorkday:
        _say('Los sábados, domingos y festivos no gastan días de vacaciones');
      case VacationTap.outOfRange:
        _say('Ese día queda fuera de tus vacaciones configuradas');
      case VacationTap.failed:
        _say('No se ha podido guardar. Vuelve a intentarlo.');
    }
  }

  /// Menú del día marcado: medio día o día entero, y el año al que cuenta
  /// (012, RF-9).
  Future<void> _longPress(DateTime date) async {
    _undo?.dismiss();
    final day = _v.dayOn(date);
    if (day == null) {
      _say(
        'Toca el día para marcarlo; después mantenlo pulsado para hacerlo '
        'medio día o cambiar su año',
      );
      return;
    }
    final other = day.countsForPreviousYear ? date.year : date.year - 1;
    final canSwitch = other >= _v.settings!.firstYear;
    final choice = await showModalBottomSheet<_DayAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                0,
                Space.gutter,
                Space.s,
              ),
              child: Text(_longDate(date), style: AppText.title),
            ),
            ListTile(
              leading: Icon(day.half ? Icons.crop_square : Icons.contrast),
              title: Text(day.half ? 'Día entero' : 'Medio día'),
              subtitle: Text(day.half ? 'Gasta 1 día' : 'Gasta solo 0,5 días'),
              onTap: () => Navigator.of(context).pop(_DayAction.half),
            ),
            if (canSwitch)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text('Contar para $other'),
                subtitle: Text('Ahora cuenta para ${day.year}'),
                onTap: () => Navigator.of(context).pop(_DayAction.year),
              ),
            const SizedBox(height: Space.s),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _DayAction.half:
        final ok = await _v.setHalf(date, !day.half);
        if (!mounted) return;
        _say(
          !ok
              ? 'No se ha podido guardar. Vuelve a intentarlo.'
              : '${_shortDate(date)}: ${day.half ? 'día entero' : 'medio día'}',
        );
      case _DayAction.year:
        final year = await _v.switchYear(date);
        if (!mounted) return;
        _say(
          year == null
              ? 'No se ha podido guardar. Vuelve a intentarlo.'
              : '${_shortDate(date)}: cuenta para $year',
        );
    }
  }

  static String _longDate(DateTime d) => '${d.day} de ${monthName(d.month)}';

  void _openSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VacationSettingsScreen(vacation: _v),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Vacaciones'), actions: widget.actions),
    body: ListenableBuilder(
      listenable: _v,
      builder: (context, _) => switch (_v.status) {
        VacationStatus.loading => const Center(
          child: StateMessage.loading(message: 'Abriendo…'),
        ),
        VacationStatus.error => Center(
          child: StateMessage.error(
            title: 'No se pueden abrir las vacaciones',
            message:
                'No se ha borrado nada. Vuelve a intentarlo; si sigue '
                'fallando, reinicia la app.',
            actionLabel: 'Reintentar',
            onAction: _v.load,
          ),
        ),
        VacationStatus.ready when !_v.isConfigured => Center(
          child: StateMessage.empty(
            title: 'Configura tus vacaciones',
            message:
                'Di desde qué año llevas la cuenta y cuántos días te '
                'corresponden. Después marca los días en el calendario.',
            actionLabel: 'Configurar',
            onAction: _openSettings,
          ),
        ),
        VacationStatus.ready => _ready(context),
      },
    ),
  );

  Widget _ready(BuildContext context) {
    final c = context.colors;
    final o = _v.overview!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.s,
        Space.gutter,
        Space.xxxl,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Te quedan',
                    style: AppText.label.copyWith(color: c.textSoft),
                  ),
                  Text(
                    daysText(o.leftHalfDays),
                    style: AppText.display.copyWith(color: c.vacation.strong),
                  ),
                  if (o.plannedHalfDays > 0)
                    Text(
                      o.plannedHalfDays == 2
                          ? 'incluye 1 día planificado'
                          : 'incluye ${daysText(o.plannedHalfDays)} '
                                'planificados',
                      style: AppText.body.copyWith(color: c.textSoft),
                    ),
                ],
              ),
            ),
            const InfoButton(
              title: 'Te quedan',
              text:
                  'Son los días generados desde tu primer año hasta este, '
                  'menos todos los días marcados, también los que tengas '
                  'planificados. Los días del año que viene se generan el 1 '
                  'de enero.',
            ),
          ],
        ),
        if (_v.saveFailed)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              'No se ha podido guardar el último cambio. Vuelve a intentarlo.',
              style: AppText.body.copyWith(color: c.error),
            ),
          ),
        const SizedBox(height: Space.l),
        _monthHeader(context),
        const SizedBox(height: Space.s),
        Mosaic(
          key: ValueKey(_month),
          days: _monthDays(),
          showLegend: false,
          markOf: dayMarksOf(context),
          onTap: _tap,
          onLongPress: _longPress,
        ),
        const SizedBox(height: Space.s),
        _legend(context),
        for (final warning in _holidayWarnings())
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(warning, style: AppText.body.copyWith(color: c.error)),
          ),
        const SizedBox(height: Space.xl),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<VacationView>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: VacationView.ownYear,
                label: Text('Por año de vacaciones'),
              ),
              ButtonSegment(
                value: VacationView.calendarYear,
                label: Text('Por año natural'),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (v) => setState(() => _view = v.first),
          ),
        ),
        const SizedBox(height: Space.s),
        ..._view == VacationView.ownYear
            ? _ownRows(context, o)
            : _calendarRows(context, o),
      ],
    );
  }

  Widget _monthHeader(BuildContext context) {
    final title = monthYear(_month.year, _month.month);
    final marked = _v.days.keys
        .where((d) => d.year == _month.year && d.month == _month.month)
        .length;
    return Row(
      children: [
        IconButton(
          tooltip: 'Mes anterior',
          onPressed: _canGo(-1) ? () => _go(-1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: TextButton.icon(
            key: const ValueKey('elegir-mes'),
            onPressed: _pickMonth,
            icon: const Icon(Icons.expand_more),
            iconAlignment: IconAlignment.end,
            label: DecoratedMonthTitle(
              year: _month.year,
              month: _month.month,
              title: Text(
                marked == 0 ? title : '$title · $marked',
                style: AppText.bodyStrong,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Mes siguiente',
          onPressed: _canGo(1) ? () => _go(1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  /// Ir a un mes de cualquier año (011, RF-1).
  Future<void> _pickMonth() async {
    final s = _v.settings!;
    final (first, last) = vacationRange(s, _v.today);
    final picked = await showMonthPicker(
      context,
      initial: _month,
      first: first,
      last: last,
    );
    if (picked != null && mounted) setState(() => _month = picked);
  }

  /// Los días del mes: los de vacaciones en amarillo y, si cuentan para el año
  /// anterior, con «’25» debajo (010, RF-10); los que no gastan días,
  /// atenuados (011, RF-3).
  List<MosaicDay> _monthDays() {
    final count = DateUtils.getDaysInMonth(_month.year, _month.month);
    final calendar = _v.calendar;
    return [
      for (var d = 1; d <= count; d++)
        () {
          final date = DateTime(_month.year, _month.month, d);
          final day = _v.dayOn(date);
          if (day == null) {
            return canTakeVacation(date, calendar: calendar)
                ? MosaicDay(date)
                : MosaicDay.muted(date);
          }
          final prev = day.countsForPreviousYear;
          if (day.half) {
            // «½» además del color a medias, para que no dependa solo de él.
            return MosaicDay.half(
              date,
              DataKind.vacation,
              prev ? '½ ${_shortYear(day.year)}' : '½',
              prev ? 'se descuenta de ${day.year}' : null,
            );
          }
          return MosaicDay(
            date,
            DataKind.vacation,
            prev ? _shortYear(day.year) : null,
            prev ? 'se descuenta de ${day.year}' : null,
          );
        }(),
    ];
  }

  static String _shortYear(int year) =>
      '’${(year % 100).toString().padLeft(2, '0')}';

  /// La explicación de «’25» solo cuando hay días así en el mes (011, RF-2).
  Widget _legend(BuildContext context) {
    final c = context.colors;
    final previous = {
      for (final d in _v.days.values)
        if (d.date.year == _month.year &&
            d.date.month == _month.month &&
            d.countsForPreviousYear)
          d.year,
    };
    return Text(
      [
        // Sola es una indicación corta, sin punto; con más frases, párrafo.
        previous.isEmpty
            ? 'Toca un día para marcarlo o quitarlo'
            : 'Toca un día para marcarlo o quitarlo.',
        for (final y in previous)
          '${_shortYear(y)}: estos días se descuentan de las vacaciones de '
              '$y. Mantén pulsado un día para cambiarlo.',
      ].join(' '),
      style: AppText.caption.copyWith(color: c.textSoft),
    );
  }

  /// Días marcados del mes que ya no son laborables (RF-11).
  List<String> _holidayWarnings() => [
    for (final d in _v.days.keys.where(
      (d) => d.year == _month.year && d.month == _month.month,
    ))
      if (!canTakeVacation(d, calendar: _v.calendar))
        'El ${d.day} de ${monthName(d.month)} no es laborable: quítalo si no '
            'te gastó un día.',
  ];

  void _openYear(int year) => setState(() => _month = DateTime(year));

  /// Se ven el año actual, el anterior y los posteriores; los demás van en un
  /// desplegable (011, RF-4).
  List<Widget> _yearCards(
    BuildContext context,
    List<({int year, String detail, int? leftHalfDays, String tag})> years,
  ) {
    final now = _v.today.year;
    final recent = [
      for (final y in years)
        if (y.year >= now - 1) y,
    ];
    final older = [
      for (final y in years)
        if (y.year < now - 1) y,
    ];
    Widget card(({int year, String detail, int? leftHalfDays, String tag}) y) =>
        _YearCard(
          key: ValueKey('fila-${y.year}'),
          year: y.year,
          detail: y.detail,
          tag: y.tag,
          leftHalfDays: y.leftHalfDays,
          onTap: () => _openYear(y.year),
        );
    // En la vista por año de vacaciones, el desplegable lleva la suma de lo
    // que les queda y se abre solo si alguno está en negativo, para que lo
    // que se ve siempre cuadre con el total (012, RF-8).
    final withBalance = older.any((y) => y.leftHalfDays != null);
    final olderLeft = older.fold(0, (a, y) => a + (y.leftHalfDays ?? 0));
    final anyNegative = older.any((y) => (y.leftHalfDays ?? 0) < 0);
    return [
      for (final y in recent) card(y),
      if (older.isNotEmpty)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey('anteriores-$withBalance'),
            initiallyExpanded: anyNegative,
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(
              withBalance
                  ? 'Años anteriores (${older.length}) · '
                        '${formatHalfDays(olderLeft)}'
                  : 'Años anteriores (${older.length})',
              style: AppText.bodyStrong.copyWith(
                color: withBalance && olderLeft < 0
                    ? context.colors.error
                    : null,
              ),
            ),
            children: [for (final y in older) card(y)],
          ),
        ),
    ];
  }

  List<Widget> _ownRows(BuildContext context, VacationOverview o) =>
      _yearCards(context, [
        for (final r in o.byOwnYear.reversed)
          (
            year: r.year,
            detail:
                'Generados ${formatHalfDays(r.generatedHalfDays)} · '
                'Disfrutados ${formatHalfDays(r.usedHalfDays)}',
            leftHalfDays: r.leftHalfDays,
            tag: 'Quedan ${formatHalfDays(r.leftHalfDays)}',
          ),
      ]);

  List<Widget> _calendarRows(BuildContext context, VacationOverview o) =>
      _yearCards(context, [
        for (final e in o.byCalendarYear.entries.toList().reversed)
          (
            year: e.key,
            detail: 'Días disfrutados ese año',
            leftHalfDays: null,
            tag: daysText(e.value),
          ),
      ]);
}

/// Tarjeta de un año: lo que quedan va en una etiqueta amarilla (quedan), gris
/// (0) o roja (negativo) (011, RF-4).
class _YearCard extends StatelessWidget {
  const _YearCard({
    super.key,
    required this.year,
    required this.detail,
    required this.tag,
    required this.leftHalfDays,
    required this.onTap,
  });

  final int year;
  final String detail;
  final String tag;

  /// Nulo en la vista por año natural: la etiqueta va en gris.
  final int? leftHalfDays;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final left = leftHalfDays;
    final (bg, fg) = left == null || left == 0
        ? (c.empty, c.text)
        : left > 0
        ? (c.vacation.fill, c.vacation.onFill)
        : (c.error, c.background);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.medium),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.medium),
          child: Container(
            padding: const EdgeInsets.all(Space.l),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.medium),
              border: Border.all(color: c.line),
            ),
            // El año y lo que queda en una línea; el detalle debajo, a todo
            // el ancho, para que no se parta.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('$year', style: AppText.title)),
                    const SizedBox(width: Space.s),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.m,
                        vertical: Space.xs,
                      ),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(Radii.large),
                      ),
                      child: Text(
                        tag,
                        style: AppText.label.copyWith(color: fg),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Text(detail, style: AppText.body.copyWith(color: c.textSoft)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que se puede hacer con un día marcado al mantenerlo pulsado.
enum _DayAction { half, year }
