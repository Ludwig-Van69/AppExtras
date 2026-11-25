import 'package:flutter/material.dart';

import '../../domain/metrics.dart';
import '../company/company_controller.dart';
import '../components/info_button.dart';
import '../components/motion_bits.dart';
import '../components/state_message.dart';
import '../format.dart';
import '../holidays/holidays_controller.dart';
import '../money/money_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../vacation/vacation_controller.dart';
import 'evolution_chart.dart';

const _initials = ['E', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
const _weekdays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

const _approxInfo =
    'Algunas horas son de antes de tu primera tarifa y se han contado con '
    'esa tarifa, así que sus euros son aproximados (antes se cobraba '
    'menos). Si pones las tarifas antiguas en Ajustes → Tarifas, la cifra '
    'sale exacta.';

/// Métricas: cómo van las horas extra a lo largo del tiempo (014, 015).
/// Solo lee lo que ya existe; no guarda nada.
class MetricsScreen extends StatefulWidget {
  const MetricsScreen({
    super.key,
    required this.money,
    this.holidays,
    this.vacation,
    this.company,
    this.actions = const [],
  });

  final MoneyController money;
  final HolidaysController? holidays;
  final VacationController? vacation;

  /// La empresa: con fecha de alta, la antigüedad arriba (026, RF-4).
  final CompanyController? company;

  /// Botones extra de la barra de título (el engranaje de Ajustes).
  final List<Widget> actions;

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends State<MetricsScreen> {
  var _all = false;
  int? _year;

  /// Mes tocado en el gráfico; nulo: el actual (o el último).
  int? _selected;

  /// Las dos vistas se deslizan, como las pestañas de Extra (017, RF-1).
  final _pages = PageController();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Cambia de vista con el botón (o al tocar un año) y mueve la página.
  void _show({required bool all, int? year}) {
    setState(() {
      _all = all;
      if (year != null) _year = year;
      _selected = null;
    });
    if (!_pages.hasClients) return;
    final target = all ? 1 : 0;
    final duration = context.motion(Motion.slide);
    if (duration == Duration.zero) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(target, duration: duration, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = widget.money;
    return Scaffold(
      appBar: AppBar(title: const Text('Métricas'), actions: widget.actions),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          money,
          ?widget.holidays,
          ?widget.vacation,
          ?widget.company,
        ]),
        builder: (context, _) => switch (money.status) {
          MoneyStatus.loading => const Center(
            child: StateMessage.loading(message: 'Calculando…'),
          ),
          MoneyStatus.error => Center(
            child: StateMessage.error(
              title: 'No se pueden calcular las métricas',
              message:
                  'No se ha borrado nada. Vuelve a intentarlo; si sigue '
                  'fallando, reinicia la app.',
              actionLabel: 'Reintentar',
              onAction: money.load,
            ),
          ),
          MoneyStatus.ready => _ready(context),
        },
      ),
    );
  }

  /// Los euros de una cifra: «874,00 €», «aprox.» o «•••• €» (015, RF-4).
  String _euros(Figure f) {
    if (widget.money.hideAmounts) return '•••• €';
    final text = formatEuros(f.cents);
    if (f.missing) return '$text (falta tarifa)';
    return f.approx ? '$text aprox.' : text;
  }

  /// «Empresa · desde el 2 mar 2020 · 6 años, 8 meses y 23 días · 2.459 días»;
  /// nula sin fecha de alta (RF-4, RF-5).
  String? _seniorityLine() {
    final company = widget.company;
    final start = company?.company.start;
    final s = company?.seniority;
    if (company == null || start == null || s == null) return null;
    return [
      ?company.company.name,
      'desde el ${shortDate(start)}',
      if (s.years > 0 || s.months > 0) s.phrase,
      '${formatCount(s.totalDays)} ${s.totalDays == 1 ? 'día' : 'días'}',
    ].join(' · ');
  }

  String _hours(int minutes) => '${formatMinutes(minutes)} h';

  Widget _ready(BuildContext context) {
    final money = widget.money;
    final today = money.today;
    final first = firstMetricsYear(money.overview.months) ?? today.year;
    final year = (_year ?? today.year).clamp(first, today.year);

    ListView page(List<Widget> children) => ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        0,
        Space.gutter,
        Space.xxxl,
      ),
      children: children,
    );

    return Column(
      children: [
        if (_seniorityLine() case final line?)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.s,
              Space.gutter,
              0,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                line,
                style: AppText.body.copyWith(color: context.colors.textSoft),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.s,
            Space.gutter,
            0,
          ),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Año')),
                ButtonSegment(value: true, label: Text('Todos los años')),
              ],
              selected: {_all},
              onSelectionChanged: (v) => _show(all: v.first),
            ),
          ),
        ),
        Expanded(
          child: PageView(
            controller: _pages,
            onPageChanged: (i) => setState(() {
              _all = i == 1;
              _selected = null;
            }),
            children: [
              page(_yearView(context, year, first, today)),
              page(_global(context)),
            ],
          ),
        ),
      ],
    );
  }

  // ---- Un año ------------------------------------------------------------

  List<Widget> _yearView(
    BuildContext context,
    int year,
    int first,
    DateTime today,
  ) {
    final c = context.colors;
    final money = widget.money;
    final calendar = widget.holidays?.calendar;
    final m = computeYearMetrics(
      months: money.overview.months,
      rates: money.rates,
      year: year,
      today: today,
      isHoliday: calendar == null ? null : (d) => calendar.holidayOn(d) != null,
      isVacation: widget.vacation == null
          ? null
          : (d) => widget.vacation!.dayOn(d) != null,
    );
    return [
      Row(
        children: [
          IconButton(
            tooltip: 'Año anterior',
            onPressed: year > first
                ? () => setState(() {
                    _year = year - 1;
                    _selected = null;
                  })
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                '$year',
                textAlign: TextAlign.center,
                style: AppText.bodyStrong,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Año siguiente',
            onPressed: year < today.year
                ? () => setState(() {
                    _year = year + 1;
                    _selected = null;
                  })
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      if (m.empty)
        const Padding(
          padding: EdgeInsets.only(top: Space.xxl),
          child: StateMessage.empty(
            title: 'Sin horas en este año',
            message: 'Cuando apuntes horas, aquí verás cómo van.',
          ),
        )
      else ...[
        _totalBlock(
          context,
          'Total del año',
          m.total,
          m.normal,
          m.festive,
          comparison: m.comparison,
        ),
        const SizedBox(height: Space.xl),
        _BarChart(
          metrics: m,
          label: (b) =>
              '${monthYear(b.month.year, b.month.month)} · '
              '${_hours(b.figure.minutes)} · ${_euros(b.figure)}'
              '${b.previous == null ? '' : ' (${b.month.year - 1}: ${_hours(b.previous!.minutes)})'}',
          selected: _selected,
          onSelect: (i) => setState(() => _selected = i),
        ),
        const SizedBox(height: Space.xl),
        _figureRow(
          context,
          'Media por mes',
          m.average,
          empty: 'Aún no hay meses terminados',
          info:
              'Solo cuenta los meses ya terminados, desde el primero con '
              'horas. El mes en curso no entra: aún no ha acabado.',
        ),
        if (m.forecast != null) ...[
          const SizedBox(height: Space.l),
          _figureRow(
            context,
            'Estimación de fin de año',
            m.forecast,
            info:
                'Es una estimación, no una cifra segura: lo que llevas más '
                'lo que harías en los días que faltan si siguieras al mismo '
                'ritmo que en lo que va de año. Va redondeada.',
          ),
        ],
        const SizedBox(height: Space.xl),
        _weekdaysBlock(context, m),
        const SizedBox(height: Space.xl),
        Text(
          'Días con horas extra',
          style: AppText.label.copyWith(color: c.textSoft),
        ),
        Text(
          '${m.workdaysWithHours} de ${m.workdays} días laborables',
          style: AppText.bodyStrong,
        ),
        Text(
          'Laborables: de lunes a viernes, sin festivos ni vacaciones',
          style: AppText.caption.copyWith(color: c.textSoft),
        ),
      ],
    ];
  }

  // ---- Todos los años ----------------------------------------------------

  List<Widget> _global(BuildContext context) {
    final c = context.colors;
    final money = widget.money;
    final g = computeGlobalMetrics(
      months: money.overview.months,
      rates: money.rates,
      today: money.today,
    );
    if (g.empty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: Space.xxl),
          child: StateMessage.empty(
            title: 'Aún no hay horas',
            message: 'Cuando apuntes horas, aquí verás su evolución.',
          ),
        ),
      ];
    }
    final best = g.bestYear;
    final places = podium(g.years);
    final bestMonth = g.bestMonth;
    return [
      const SizedBox(height: Space.l),
      _totalBlock(
        context,
        'Total desde ${g.series.first.month.year}',
        g.total,
        g.normal,
        g.festive,
      ),
      const SizedBox(height: Space.xl),
      Text('Evolución', style: AppText.label.copyWith(color: c.textSoft)),
      const SizedBox(height: Space.s),
      EvolutionChart(
        points: g.series,
        label: (p) =>
            '${monthYear(p.month.year, p.month.month)} · '
            '${_hours(p.figure.minutes)} · ${_euros(p.figure)}',
        averageLabel: (minutes) => 'Media de 12 meses: ${_hours(minutes)}',
      ),
      const SizedBox(height: Space.xl),
      _figureRow(
        context,
        'Media por año',
        g.averagePerYear,
        empty: 'Aún no hay años terminados',
        info: 'Solo cuenta los años ya terminados: el actual no entra.',
      ),
      const SizedBox(height: Space.l),
      _figureRow(
        context,
        'Media por mes',
        g.averagePerMonth,
        empty: 'Aún no hay meses terminados',
        info:
            'Solo cuenta los meses ya terminados, desde el primero con '
            'horas. Los meses sin horas cuentan como cero.',
      ),
      if (best != null) ...[
        const SizedBox(height: Space.l),
        _figureRow(context, 'Año con más horas: ${best.year}', best.figure),
      ],
      if (bestMonth != null) ...[
        const SizedBox(height: Space.l),
        _figureRow(
          context,
          'Mes con más horas: '
          '${monthYear(bestMonth.month.year, bestMonth.month.month)}',
          bestMonth.figure,
        ),
      ],
      const SizedBox(height: Space.xl),
      Text('Por años', style: AppText.label.copyWith(color: c.textSoft)),
      for (final y in g.years) _yearRow(context, y, places[y.year]),
    ];
  }

  /// Fila de un año, con su trofeo si está en el podio (018, RF-6, RF-7).
  Widget _yearRow(BuildContext context, YearRow y, int? place) {
    final c = context.colors;
    const placeNames = ['primero', 'segundo', 'tercero'];
    return Semantics(
      button: true,
      label:
          '${y.year}: ${hoursPhrase(y.figure.minutes)}, '
          '${_euros(y.figure)}'
          '${place == null ? '' : ', ${placeNames[place - 1]} en horas'}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.control),
        onTap: () => _show(all: false, year: y.year),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.m),
          child: Row(
            children: [
              Text('${y.year}', style: AppText.bodyStrong),
              if (place != null)
                Padding(
                  padding: const EdgeInsets.only(left: Space.s),
                  // Oro, plata y bronce aparecen uno tras otro, con esperas
                  // que se acortan (bloque G).
                  child: AppearOnce(
                    delay: const [
                      Duration.zero,
                      Duration(milliseconds: 70),
                      Duration(milliseconds: 120),
                    ][place - 1],
                    child: Icon(
                      Icons.emoji_events,
                      key: ValueKey('trofeo-$place'),
                      size: 20,
                      color: c.medals[place - 1],
                    ),
                  ),
                ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_hours(y.figure.minutes), style: AppText.bodyStrong),
                    Text(
                      _euros(y.figure),
                      textAlign: TextAlign.right,
                      style: AppText.caption.copyWith(color: c.textSoft),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.textSoft),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Piezas comunes ----------------------------------------------------

  Widget _totalBlock(
    BuildContext context,
    String label,
    Figure total,
    Figure normal,
    Figure festive, {
    YearComparison? comparison,
  }) {
    final c = context.colors;
    String? cmpText;
    if (comparison != null) {
      final d = comparison.difference;
      String sign(int v) => v > 0 ? '+' : (v < 0 ? '−' : '');
      final hours = d.minutes == 0
          ? 'Igual'
          : '${sign(d.minutes)}${_hours(d.minutes.abs())}';
      final euros = widget.money.hideAmounts
          ? '•••• €'
          : '${sign(d.cents)}${formatEuros(d.cents.abs())}';
      final until = comparison.until;
      cmpText =
          '$hours · $euros frente a ${comparison.previousYear}'
          '${until == null ? '' : ' a ${until.day} de ${monthName(until.month)}'}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppText.label.copyWith(color: c.textSoft),
              ),
            ),
            InfoButton(
              title: 'Qué se cuenta',
              text:
                  'Cada hora cuenta en el mes en que se hizo, no en el que se '
                  'cobró. Cuentan todas las horas apuntadas, también las que '
                  'apartaste a la bolsa o a la reserva. Los euros son los de '
                  'Resumen: a la tarifa de cada día y ya restado lo apartado. '
                  'No entran multas ni extras.'
                  '${total.approx ? '\n\n$_approxInfo' : ''}',
            ),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _hours(total.minutes),
            key: const ValueKey('metricas-total'),
            style: AppText.display.copyWith(color: c.normal.strong),
          ),
        ),
        Text(
          _euros(total),
          key: const ValueKey('metricas-total-euros'),
          style: AppText.bodyStrong.copyWith(color: c.textSoft),
        ),
        const SizedBox(height: Space.s),
        Text(
          'Normales ${_hours(normal.minutes)} · ${_euros(normal)}',
          style: AppText.body.copyWith(color: c.textSoft),
        ),
        Text(
          'Festivas ${_hours(festive.minutes)} · ${_euros(festive)}',
          style: AppText.body.copyWith(color: c.textSoft),
        ),
        if (cmpText != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              cmpText,
              key: const ValueKey('metricas-comparacion'),
              style: AppText.body.copyWith(color: c.text),
            ),
          ),
      ],
    );
  }

  /// Una cifra con su etiqueta: horas grandes y euros debajo (015, RF-2).
  Widget _figureRow(
    BuildContext context,
    String label,
    Figure? figure, {
    String? empty,
    String? info,
  }) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.label.copyWith(color: c.textSoft)),
              if (figure == null)
                Text(empty ?? '', style: AppText.body)
              else ...[
                Text(_hours(figure.minutes), style: AppText.figure),
                Text(
                  _euros(figure),
                  style: AppText.caption.copyWith(color: c.textSoft),
                ),
              ],
            ],
          ),
        ),
        if (info != null) InfoButton(title: label, text: info),
      ],
    );
  }

  Widget _weekdaysBlock(BuildContext context, YearMetrics m) {
    final c = context.colors;
    final values = m.weekdayMinutes;
    final max = values.fold(0, (a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Horas por día de la semana',
          style: AppText.label.copyWith(color: c.textSoft),
        ),
        const SizedBox(height: Space.s),
        for (var i = 0; i < 7; i++)
          Semantics(
            label: '${_weekdays[i]}: ${hoursPhrase(values[i])}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs / 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      _weekdays[i].substring(0, 2),
                      style: AppText.caption.copyWith(color: c.textSoft),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 8,
                          width: max == 0 ? 0 : box.maxWidth * values[i] / max,
                          decoration: BoxDecoration(
                            // El día de más horas, destacado (014, RF-12).
                            color: values[i] == max && max > 0
                                ? c.normal.strong
                                : c.outline,
                            borderRadius: BorderRadius.circular(Radii.tiny),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      _hours(values[i]),
                      textAlign: TextAlign.right,
                      style: AppText.caption.copyWith(color: c.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Barras de un año, siempre en horas (014, RF-14; 015, RF-3). Sin escala:
/// la cifra exacta sale arriba al tocar una barra.
class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.metrics,
    required this.label,
    required this.selected,
    required this.onSelect,
  });

  final YearMetrics metrics;
  final String Function(MonthBar) label;
  final int? selected;
  final ValueChanged<int> onSelect;

  static const _height = 164.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bars = metrics.bars;
    final current = bars.indexWhere((b) => b.isCurrent);
    final shown = selected ?? (current >= 0 ? current : bars.length - 1);
    final max = bars.fold(0, (a, b) {
      final p = b.previous?.minutes ?? 0;
      final v = b.figure.minutes > p ? b.figure.minutes : p;
      return v > a ? v : a;
    });
    final hasPrevious = bars.any((b) => b.previous != null);
    // La barra más alta ocupa todo el hueco que deja la inicial del mes,
    // que crece con la letra grande.
    double h(int v, double room) =>
        max <= 0 || v <= 0 ? 0 : (room * v / max).clamp(3, room);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            label(bars[shown]),
            key: const ValueKey('metricas-barra-elegida'),
            style: AppText.bodyStrong,
          ),
        ),
        const SizedBox(height: Space.s),
        SizedBox(
          height: _height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < bars.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == shown,
                    label: label(bars[i]),
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelect(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, box) => Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _bar(
                                    h(bars[i].figure.minutes, box.maxHeight),
                                    bars[i].isCurrent
                                        ? c.normal.strong
                                        : c.outline,
                                    width: 10,
                                  ),
                                  if (bars[i].previous != null) ...[
                                    const SizedBox(width: 2),
                                    _bar(
                                      h(
                                        bars[i].previous!.minutes,
                                        box.maxHeight,
                                      ),
                                      c.line,
                                      width: 5,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            _initials[bars[i].month.month - 1],
                            style: AppText.caption.copyWith(
                              color: i == shown ? c.text : c.textSoft,
                              fontWeight: i == shown
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              decoration: i == shown
                                  ? TextDecoration.underline
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasPrevious) ...[
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.l,
            children: [
              _legend(c.outline, '${metrics.year}'),
              _legend(c.line, '${metrics.year - 1}'),
            ],
          ),
        ],
      ],
    );
  }

  Widget _bar(double height, Color color, {required double width}) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    ),
  );

  Widget _legend(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: Sizes.legendSwatch,
        height: Sizes.legendSwatch,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(Radii.tiny),
        ),
      ),
      const SizedBox(width: Space.tileGap),
      Text(text, style: AppText.caption),
    ],
  );
}
