import 'package:flutter/material.dart';

import '../../domain/day_kind.dart';
import '../../domain/money.dart';
import '../../domain/saved_hours.dart';
import '../components/info_button.dart';
import '../components/motion_bits.dart';
import '../components/roll_switcher.dart';
import '../components/state_message.dart';
import '../extras/extras_controller.dart';
import '../format.dart';
import '../saved/saved_hours_view.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'money_controller.dart';
import 'rates_screen.dart';
import '../vacation/vacation_controller.dart';
import '../vacation/vacation_screen.dart';

String _euros(MoneyController c, int cents) =>
    c.hideAmounts ? '•••• €' : formatEuros(cents);

String _statusName(MonthStatus s) => switch (s) {
  MonthStatus.open => 'Abierto',
  MonthStatus.delivered => 'Entregado',
  MonthStatus.paid => 'Cobrado',
};

/// Etiqueta del estado de un mes, con icono y color (006, RF-1).
class _StatusTag extends StatelessWidget {
  const _StatusTag(this.status);
  final MonthStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, fg, bg) = switch (status) {
      MonthStatus.open => (Icons.schedule, c.text, c.empty),
      MonthStatus.delivered => (
        Icons.outgoing_mail,
        c.normal.onStrong,
        c.normal.strong,
      ),
      MonthStatus.paid => (Icons.check_circle, c.textSoft, Colors.transparent),
    };
    final name = _statusName(status);
    return Container(
      key: ValueKey('estado-$name'),
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.tiny),
        border: status == MonthStatus.paid ? Border.all(color: c.line) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: Space.xs),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

String _shortDate(DateTime d) =>
    '${d.day} ${monthName(d.month).substring(0, 3)}';

/// Sección «Resumen»: lo que se debe y los meses (005, RF-5, RF-7, RF-10), y
/// el total aparte con multas y extras (007, RF-9 a RF-12).
class MoneyScreen extends StatelessWidget {
  const MoneyScreen({
    super.key,
    required this.money,
    this.extras,
    this.onOpenExtras,
    this.onOpenSaved,
    this.vacation,
    this.onOpenVacation,
    this.actions = const [],
    this.header,
  });

  /// Lo que va arriba del todo, antes de «A cobrar»: la tarjeta «Primeros
  /// pasos» (024, RF-1).
  final Widget? header;

  final MoneyController money;
  final ExtrasController? extras;
  final VoidCallback? onOpenExtras;

  /// Abre Extra en la pestaña «Horas guardadas» (009, RF-4).
  final VoidCallback? onOpenSaved;

  /// Las vacaciones y cómo abrir su sección (010, RF-18).
  final VacationController? vacation;
  final VoidCallback? onOpenVacation;

  /// Botones extra de la barra de título (el engranaje de Ajustes).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumen'),
        actions: [
          ListenableBuilder(
            listenable: money,
            builder: (context, _) => IconButton(
              tooltip: money.hideAmounts
                  ? 'Mostrar importes'
                  : 'Ocultar importes',
              icon: Icon(
                money.hideAmounts
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: money.toggleHideAmounts,
            ),
          ),
          ...actions,
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([money, ?extras, ?vacation]),
        builder: (context, _) => switch (money.status) {
          MoneyStatus.loading => const Center(
            child: StateMessage.loading(message: 'Calculando…'),
          ),
          MoneyStatus.error => Center(
            child: StateMessage.error(
              title: 'No se puede calcular el dinero',
              message:
                  'No se ha borrado nada. Vuelve a intentarlo; si sigue '
                  'fallando, reinicia la app.',
              actionLabel: 'Reintentar',
              onAction: money.load,
            ),
          ),
          MoneyStatus.ready => _Ready(
            money: money,
            extras: extras,
            onOpenExtras: onOpenExtras,
            onOpenSaved: onOpenSaved,
            vacation: vacation,
            onOpenVacation: onOpenVacation,
            header: header,
          ),
        },
      ),
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({
    required this.money,
    this.extras,
    this.onOpenExtras,
    this.onOpenSaved,
    this.vacation,
    this.onOpenVacation,
    this.header,
  });
  final Widget? header;
  final VacationController? vacation;
  final VoidCallback? onOpenVacation;
  final MoneyController money;
  final ExtrasController? extras;
  final VoidCallback? onOpenExtras;
  final VoidCallback? onOpenSaved;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = money.overview;
    final late = o.unsubmittedBefore(money.today);
    final waiting = o.deliveredUnpaid;
    final unpaid = o.months.where((m) => m.status != MonthStatus.paid).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.s,
        Space.gutter,
        Space.xxxl,
      ),
      children: [
        ?header,
        Text('A cobrar', style: AppText.label.copyWith(color: c.textSoft)),
        // «51 h = 765,00 €» (018, RF-1).
        _RollingTotal(
          cents: o.toCollectCents,
          text:
              '${formatMinutes(o.toCollectMinutes)} h = '
              '${_euros(money, o.toCollectCents)}',
          child: Text.rich(
            key: const ValueKey('cabecera-cobrar'),
            TextSpan(
              children: [
                TextSpan(text: '${formatMinutes(o.toCollectMinutes)} h'),
                TextSpan(
                  text: ' = ',
                  style: TextStyle(color: c.textSoft),
                ),
                TextSpan(
                  text: _euros(money, o.toCollectCents),
                  style: TextStyle(color: c.normal.strong),
                ),
              ],
            ),
            style: AppText.display.copyWith(color: c.text),
          ),
        ),
        // Su cuenta, como la de lo entregado (018, RF-1).
        _BreakdownLines(
          key: const ValueKey('desglose-cobrar'),
          money: money,
          breakdown: HoursBreakdown.of(unpaid),
        ),
        if (waiting.isNotEmpty)
          _DeliveredBox(money: money, breakdown: HoursBreakdown.of(waiting)),
        if (extras?.status == ExtrasStatus.ready)
          _TotalLine(
            label: 'Con multas y extras',
            text: _euros(money, extras!.totals.withHours(o.toCollectCents)),
            onTap: onOpenExtras,
            info:
                'Es lo que cobrarías por horas, más los extras pendientes y '
                'menos las multas pendientes. Es un total posible, sin '
                'confirmar: depende de que la empresa pague los extras y te '
                'descuente las multas. Lo que ya está cobrado, descontado, '
                'anulado o descartado no cuenta. Toca la cifra para ver la '
                'lista.',
          ),
        if (money.hasSavedHours) _savedLine(c),
        if (vacation?.overview case final v?)
          _TotalLine(
            label: 'Vacaciones',
            text: 'Te quedan ${daysText(v.leftHalfDays)}',
            dot: c.vacation.fill,
            onTap: onOpenVacation,
            info:
                'Los días generados desde tu primer año hasta este, menos '
                'los días marcados, también los planificados. Toca la cifra '
                'para ver el calendario.',
          ),
        if (money.saveFailed)
          _Notice(
            icon: Icons.error_outline,
            text: 'No se ha podido guardar el último cambio. Vuelve a intentarlo.',
            color: c.error,
          ),
        if (!money.hasRates)
          _Notice(
            icon: Icons.sell_outlined,
            text: 'Pon tus tarifas para ver los importes.',
            action: 'Poner tarifas',
            onAction: () => openRates(context, money),
          )
        else if (o.hasUnpriced)
          _Notice(
            icon: Icons.warning_amber_outlined,
            text:
                'Hay horas sin tarifa (anteriores a la primera): su importe no '
                'está incluido.',
            color: c.error,
            action: 'Ver tarifas',
            onAction: () => openRates(context, money),
          ),
        if (late.isNotEmpty)
          _Notice(
            icon: Icons.mark_email_unread_outlined,
            text: late.length == 1
                ? 'Llevas 1 mes sin entregar'
                : 'Llevas ${late.length} meses sin entregar',
          ),
        if (waiting.isNotEmpty)
          _Notice(
            icon: Icons.hourglass_bottom,
            text: waiting.length == 1
                ? '1 mes entregado sin cobrar.'
                : '${waiting.length} meses entregados sin cobrar.',
          ),
        if (unpaid.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PayManyScreen(money: money),
                ),
              ),
              child: const Text('Cobrar varios meses'),
            ),
          ),
        ],
        const SizedBox(height: Space.l),
        if (o.months.isEmpty)
          Text(
            'Aún no hay horas apuntadas.',
            style: AppText.body.copyWith(color: c.textSoft),
          ),
        // Cada año en su tarjeta: el actual, desplegado; los anteriores,
        // plegados (018, RF-5).
        for (final (year, months) in _byYear(o.months))
          _YearCard(
            key: ValueKey('año-$year'),
            money: money,
            year: year,
            months: months,
            startOpen: year >= money.today.year,
            tile: (m) => _monthTile(context, m),
          ),
      ],
    );
  }
}

extension on _Ready {
  Widget _monthTile(BuildContext context, MonthLine m) {
    final c = context.colors;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: Space.s,
      title: Text(
        monthYear(m.month.year, m.month.month),
        style: AppText.bodyStrong.copyWith(
          color: m.status == MonthStatus.paid ? c.textSoft : c.text,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Space.xs),
        child: Wrap(
          spacing: Space.s,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FadeSwap(value: m.status, child: _StatusTag(m.status)),
            Text(
              '${formatMinutes(m.minutes)} h'
              '${outOfMonthText(m)}'
              '${m.isComplete ? '' : ' · falta tarifa'}',
              style: AppText.body.copyWith(
                color: m.status == MonthStatus.paid ? c.textSoft : c.text,
              ),
            ),
          ],
        ),
      ),
      trailing: Text(
        _euros(money, m.amountCents),
        style: AppText.figure.copyWith(
          color: m.status == MonthStatus.paid ? c.textSoft : c.text,
        ),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MonthScreen(money: money, month: m.month),
        ),
      ),
    );
  }

  /// «Horas guardadas: 55 h · 825,00 €» (009, RF-4).
  Widget _savedLine(AppColors c) {
    final s = money.savedSummary;
    final value = s.totalValueCents;
    return _TotalLine(
      label: 'Horas guardadas',
      text:
          '${formatMinutes(s.totalMinutes)} h · '
          '${value == null ? 'falta la tarifa' : _euros(money, value)}',
      dot: c.bag.strong,
      onTap: onOpenSaved,
      info:
          'Son las horas de la bolsa de empresa y de tu reserva. Su valor es '
          'horas × tu tarifa normal de hoy, así que cambia si cambias la '
          'tarifa. Es un valor posible, sin confirmar, y no se suma a ningún '
          'otro total: solo cuenta lo que de verdad cobres. Toca la cifra '
          'para ver los cajones y sus movimientos.',
    );
  }
}

/// Los meses agrupados por año, del más reciente al más antiguo.
List<(int, List<MonthLine>)> _byYear(List<MonthLine> months) {
  final out = <(int, List<MonthLine>)>[];
  for (final m in months) {
    if (out.isEmpty || out.last.$1 != m.month.year) {
      out.add((m.month.year, []));
    }
    out.last.$2.add(m);
  }
  return out;
}

/// Un año con su resumen; al tocarlo se pliega o se despliega (018, RF-5).
/// Empieza abierto si [startOpen] (el año en curso). No se guarda.
class _YearCard extends StatefulWidget {
  const _YearCard({
    super.key,
    required this.money,
    required this.year,
    required this.months,
    required this.tile,
    this.startOpen = false,
  });
  final bool startOpen;
  final MoneyController money;
  final int year;
  final List<MonthLine> months;
  final Widget Function(MonthLine) tile;

  @override
  State<_YearCard> createState() => _YearCardState();
}

class _YearCardState extends State<_YearCard> {
  late var _open = widget.startOpen;

  /// Los meses del año, si está abierta; aparecen con un fundido.
  Widget? _monthsOf(BuildContext context) => !_open
      ? null
      : AppearOnce(
          child: Column(
            children: [for (final m in widget.months) widget.tile(m)],
          ),
        );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final months = widget.months;
    final minutes = months.fold(0, (s, m) => s + m.minutes);
    final cents = months.fold(0, (s, m) => s + m.amountCents);
    final unpaid = months.where((m) => m.status != MonthStatus.paid).length;
    final status = unpaid == 0
        ? 'Todo cobrado'
        : unpaid == 1
        ? '1 mes sin cobrar'
        : '$unpaid meses sin cobrar';
    // La tarjeta es la cabecera; los meses van debajo, a todo lo ancho, para
    // que quepan en móviles estrechos con letra grande.
    return Padding(
      padding: const EdgeInsets.only(top: Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.medium),
            clipBehavior: Clip.antiAlias,
            child: Semantics(
              expanded: _open,
              child: InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.all(Space.m),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${widget.year}', style: AppText.bodyStrong),
                            Text(
                              '${formatMinutes(minutes)} h · '
                              '${_euros(widget.money, cents)}',
                              style: AppText.body.copyWith(color: c.textSoft),
                            ),
                            Text(
                              status,
                              key: ValueKey('estado-año-${widget.year}'),
                              style: unpaid == 0
                                  ? AppText.label.copyWith(color: c.textSoft)
                                  : AppText.label.copyWith(
                                      color: c.normal.strong,
                                      fontWeight: FontWeight.w700,
                                    ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: context.motion(Motion.expand),
                        curve: Motion.easeOut,
                        child: Icon(Icons.expand_more, color: c.textSoft),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Crece hasta su altura y los meses aparecen a la vez; al cerrar,
          // se encoge sin esperar (018; bloque G).
          // Con las animaciones reducidas no hay crecimiento (y AnimatedSize
          // con duración cero falla al medirse).
          if (context.motion(Motion.expand) == Duration.zero)
            ?_monthsOf(context)
          else
            AnimatedSize(
              duration: Motion.expand,
              curve: Motion.easeOut,
              alignment: Alignment.topCenter,
              child:
                  _monthsOf(context) ?? const SizedBox(width: double.infinity),
            ),
        ],
      ),
    );
  }
}

/// Las líneas de una cuenta: «Normales · 40 h × 15,00 € … 600,00 €», el
/// redondeo y las horas sin tarifa (018, RF-1 a RF-4).
class _BreakdownLines extends StatelessWidget {
  const _BreakdownLines({
    super.key,
    required this.money,
    required this.breakdown,
  });
  final MoneyController money;
  final HoursBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = breakdown;
    final soft = AppText.label.copyWith(color: c.textSoft);
    Widget row(String left, String right, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.only(top: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(left, style: soft)),
          const SizedBox(width: Space.s),
          Text(right, style: AppText.label.copyWith(color: c.text)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in b.lines)
          row(
            '${l.kind == DayKind.festive ? 'Festivas' : 'Normales'} · '
            '${formatMinutes(l.minutes)} h × ${_euros(money, l.rateCents)}',
            _euros(money, l.cents),
          ),
        if (b.roundingCents != 0)
          row(
            'Redondeo de cada mes',
            money.hideAmounts
                ? '•••• €'
                : '${b.roundingCents > 0 ? '+' : '−'}'
                      '${formatEuros(b.roundingCents.abs())}',
            key: const ValueKey('redondeo'),
          ),
        if (b.unpricedMinutes > 0)
          row(
            '${formatMinutes(b.unpricedMinutes)} h sin tarifa',
            'no incluidas',
          ),
      ],
    );
  }
}

/// Lo que se debe de los meses entregados, destacado y con la cuenta a la
/// vista para comprobarla con la nómina (018, RF-2 a RF-4).
class _DeliveredBox extends StatelessWidget {
  const _DeliveredBox({required this.money, required this.breakdown});
  final MoneyController money;
  final HoursBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = breakdown;
    return Container(
      key: const ValueKey('entregado-sin-cobrar'),
      margin: const EdgeInsets.only(top: Space.m),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.medium),
        border: Border.all(color: c.normal.strong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'De meses entregados',
                  style: AppText.bodyStrong.copyWith(color: c.text),
                ),
              ),
              const SizedBox(width: Space.s),
              Text(
                _euros(money, b.totalCents),
                style: AppText.figure.copyWith(color: c.normal.strong),
              ),
            ],
          ),
          _BreakdownLines(money: money, breakdown: b),
        ],
      ),
    );
  }
}

/// Un total aparte que se puede tocar, con su ⓘ: «Con multas y extras» (007,
/// RF-9) y «Horas guardadas» (009, RF-4). Que no es seguro lo dice el ⓘ
/// (009, RF-5).
class _TotalLine extends StatelessWidget {
  const _TotalLine({
    required this.label,
    required this.text,
    required this.info,
    this.dot,
    this.onTap,
  });
  final String label;
  final String text;

  /// Punto con el color de la categoría (vacaciones, horas guardadas); la
  /// cifra va siempre en el color del texto.
  final Color? dot;
  final String info;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(Radii.small),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (dot != null) ...[
                          Container(
                            width: Space.s,
                            height: Space.s,
                            decoration: BoxDecoration(
                              color: dot,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: Space.s),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            style: AppText.label.copyWith(color: c.textSoft),
                          ),
                        ),
                      ],
                    ),
                    Text(text, style: AppText.figure.copyWith(color: c.text)),
                  ],
                ),
              ),
            ),
          ),
          InfoButton(title: label, text: info),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    this.color,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? c.textSoft),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(
              text,
              style: AppText.label.copyWith(color: color ?? c.text),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// La Hoja del mes (RF-8).
class MonthScreen extends StatelessWidget {
  const MonthScreen({super.key, required this.money, required this.month});

  final MoneyController money;
  final YearMonth month;

  Future<void> _pick(BuildContext context, MonthStatus s) async {
    DateTime? date;
    if (s == MonthStatus.paid) {
      date = await showDatePicker(
        context: context,
        helpText: 'Fecha del cobro',
        initialDate: money.today,
        firstDate: DateTime(2020),
        lastDate: DateTime(money.today.year + 1, 12, 31),
      );
      if (date == null) return;
    }
    await money.setStatus(month, s, date: date);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(monthYear(month.year, month.month))),
      body: ListenableBuilder(
        listenable: money,
        builder: (context, _) {
          final matches = money.overview.months.where((l) => l.month == month);
          if (matches.isEmpty) {
            return const Center(
              child: StateMessage.empty(
                title: 'Sin horas',
                message: 'Este mes ya no tiene horas apuntadas.',
              ),
            );
          }
          final line = matches.first;
          final rec = line.record;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.s,
              Space.gutter,
              Space.xxxl,
            ),
            children: [
              Text(
                'Importe del mes',
                style: AppText.label.copyWith(color: c.textSoft),
              ),
              Text(
                _euros(money, line.amountCents),
                style: AppText.display.copyWith(color: c.normal.strong),
              ),
              Text(
                '${formatMinutes(line.minutes)} h',
                style: AppText.body.copyWith(color: c.textSoft),
              ),
              const SizedBox(height: Space.l),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<MonthStatus>(
                  showSelectedIcon: false,
                  segments: [
                    for (final s in MonthStatus.values)
                      ButtonSegment(value: s, label: Text(_statusName(s))),
                  ],
                  selected: {line.status},
                  onSelectionChanged: (v) {
                    if (v.first != line.status) _pick(context, v.first);
                  },
                ),
              ),
              if (rec?.deliveredOn != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: Text(
                    'Entregado el ${_shortDate(rec!.deliveredOn!)}'
                    '${rec.paidOn == null ? '' : ' · cobrado el ${_shortDate(rec.paidOn!)}'}',
                    style: AppText.body.copyWith(color: c.textSoft),
                  ),
                ),
              if (!line.isComplete)
                Padding(
                  padding: const EdgeInsets.only(top: Space.m),
                  child: Text(
                    'Falta la tarifa de ${formatMinutes(line.unpricedMinutes)} h: '
                    'su importe no está incluido.',
                    style: AppText.body.copyWith(color: c.error),
                  ),
                ),
              const SizedBox(height: Space.l),
              for (final kind in DayKind.values)
                if (line.minutesOf(kind) > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: Row(
                      children: [
                        Container(
                          width: Sizes.legendSwatch,
                          height: Sizes.legendSwatch,
                          decoration: BoxDecoration(
                            color: kind == DayKind.festive
                                ? c.festive.strong
                                : c.normal.strong,
                            borderRadius: BorderRadius.circular(Radii.tiny),
                          ),
                        ),
                        const SizedBox(width: Space.s),
                        Expanded(
                          child: Text(
                            '${kind == DayKind.festive ? 'Festivas' : 'Normales'} · '
                            '${formatMinutes(line.minutesOf(kind))} h',
                            style: AppText.bodyStrong,
                          ),
                        ),
                        Text(
                          _euros(money, line.amountOf(kind)),
                          style: AppText.bodyStrong,
                        ),
                      ],
                    ),
                  ),
              for (final b in [...SavedBox.values, null])
                if (line.setAside.any((s) => s.move.box == b))
                  _setAsideRow(context, line, b),
              if (line.status == MonthStatus.open)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: OutlinedButton.icon(
                    key: const ValueKey('cambiar-por-libre'),
                    onPressed: () => openSavedMove(
                      context,
                      money,
                      null,
                      SavedMoveKind.swap,
                      _swapDate(),
                    ),
                    icon: const Icon(Icons.beach_access_outlined),
                    label: const Text('Cambiar horas por tiempo libre'),
                  ),
                ),
              const Divider(height: Space.xxl),
              if (line.imported != null) ...[
                // Mes del Excel: solo su total, sin días (016, RF-5).
                Row(
                  key: const ValueKey('mes-del-excel'),
                  children: [
                    Icon(Icons.table_chart_outlined, color: c.textSoft),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: Text(
                        'Total importado del Excel: este mes no tiene días.',
                        style: AppText.body.copyWith(color: c.textSoft),
                      ),
                    ),
                  ],
                ),
                if (line.hasIgnoredDays)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.m),
                    child: Text(
                      'Este mes también tiene días apuntados, pero no cuentan: '
                      'manda el total del Excel, para no contar dos veces.',
                      key: const ValueKey('dias-ignorados'),
                      style: AppText.body.copyWith(color: c.error),
                    ),
                  ),
              ],
              for (final d in line.countedDays)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '${d.entry.date.day} de ${monthName(d.entry.date.month)}'
                    '${d.entry.kind == DayKind.festive ? ' · festiva' : ''}',
                  ),
                  subtitle: d.entry.reason == null
                      ? null
                      : Text(d.entry.reason!),
                  trailing: Text(
                    '${formatMinutes(d.entry.minutes)} h · '
                    '${d.rateCents == null ? 'sin tarifa' : _euros(money, amountCents(d.entry.minutes, d.rateCents!))}',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Fecha con que empieza un cambio por libre: hoy si es este mes; si no,
  /// el último día del mes (022, RF-7).
  DateTime _swapDate() {
    final today = money.today;
    final last = DateTime(month.year, month.month + 1, 0);
    return last.isAfter(today) ? today : last;
  }

  /// «Apartadas a Mi reserva · 3 h   −45,00 €» (008, RF-5), o «Cambiadas
  /// por tiempo libre» si [box] es nulo (022, RF-10).
  Widget _setAsideRow(BuildContext context, MonthLine line, SavedBox? box) {
    final c = context.colors;
    final mine = line.setAside.where((s) => s.move.box == box);
    final minutes = mine.fold(0, (sum, s) => sum + s.move.minutes);
    final cents = (mine.fold(0, (sum, s) => sum + s.weight) + 30) ~/ 60;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        children: [
          Container(
            width: Sizes.legendSwatch,
            height: Sizes.legendSwatch,
            decoration: BoxDecoration(
              color: c.bag.strong,
              borderRadius: BorderRadius.circular(Radii.tiny),
            ),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(
              '${box == null ? 'Cambiadas por tiempo libre' : 'Apartadas a ${box.label}'}: '
              '−${formatMinutes(minutes)} h',
              style: AppText.bodyStrong,
            ),
          ),
          Text(
            money.hideAmounts ? '−•••• €' : '−${formatEuros(cents)}',
            style: AppText.bodyStrong,
          ),
        ],
      ),
    );
  }
}

/// Cobrar varios meses de una vez (RF-9).
class PayManyScreen extends StatefulWidget {
  const PayManyScreen({super.key, required this.money});
  final MoneyController money;

  @override
  State<PayManyScreen> createState() => _PayManyScreenState();
}

class _PayManyScreenState extends State<PayManyScreen> {
  final _selected = <YearMonth>{};
  late DateTime _date = widget.money.today;
  bool _working = false;

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      helpText: 'Fecha del cobro',
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(widget.money.today.year + 1, 12, 31),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pay() async {
    setState(() => _working = true);
    final n = _selected.length;
    await widget.money.markPaid(_selected, _date);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n == 1
              ? '1 mes marcado como cobrado.'
              : '$n meses marcados como cobrados.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final money = widget.money;
    final unpaid = money.overview.months
        .where((m) => m.status != MonthStatus.paid)
        .toList();
    final total = unpaid
        .where((m) => _selected.contains(m.month))
        .fold(0, (sum, m) => sum + m.amountCents);
    return Scaffold(
      appBar: AppBar(title: const Text('Cobrar varios meses')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.s,
          Space.gutter,
          Space.xxxl,
        ),
        children: [
          for (final m in unpaid)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _selected.contains(m.month),
              onChanged: _working
                  ? null
                  : (v) => setState(
                      () => v!
                          ? _selected.add(m.month)
                          : _selected.remove(m.month),
                    ),
              title: Text(
                monthYear(m.month.year, m.month.month),
                style: AppText.bodyStrong,
              ),
              subtitle: Text(
                '${formatMinutes(m.minutes)} h · ${_statusName(m.status)}',
              ),
              secondary: Text(_euros(money, m.amountCents)),
            ),
          const SizedBox(height: Space.l),
          OutlinedButton.icon(
            onPressed: _working ? null : _pickDate,
            icon: const Icon(Icons.event),
            label: Text(
              'Cobrado el ${_date.day} de ${monthName(_date.month)} de ${_date.year}',
            ),
          ),
          const SizedBox(height: Space.s),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Text(
                'Total seleccionado: ${_euros(money, total)}',
                style: AppText.bodyStrong,
              ),
            ),
          FilledButton(
            onPressed: _selected.isEmpty || _working ? null : _pay,
            child: const Text('Marcar como cobrados'),
          ),
        ],
      ),
    );
  }
}

/// La cifra de «A cobrar»: cuando cambia (al cobrar un mes, por ejemplo),
/// rueda como un marcador, hacia abajo si baja y hacia arriba si sube.
class _RollingTotal extends StatefulWidget {
  const _RollingTotal({
    required this.cents,
    required this.text,
    required this.child,
  });

  final int cents;

  /// Lo que se ve: si cambia (también al ocultar importes), se anima.
  final String text;
  final Widget child;

  @override
  State<_RollingTotal> createState() => _RollingTotalState();
}

class _RollingTotalState extends State<_RollingTotal> {
  late int _before = widget.cents;
  var _up = true;

  @override
  void didUpdateWidget(_RollingTotal old) {
    super.didUpdateWidget(old);
    if (old.cents != widget.cents) {
      _up = widget.cents > _before;
      _before = widget.cents;
    }
  }

  @override
  Widget build(BuildContext context) => RollSwitcher(
    value: widget.text,
    forward: _up,
    vertical: true,
    clip: true,
    duration: Motion.roll,
    child: widget.child,
  );
}

/// « · 3 h apartadas · 2 h a tiempo libre» tras las horas de un mes, o nada
/// si no sale ninguna (022, RF-9).
String outOfMonthText(MonthLine m) => [
  if (m.boxedMinutes > 0) ' · ${formatMinutes(m.boxedMinutes)} h apartadas',
  if (m.swappedMinutes > 0)
    ' · ${formatMinutes(m.swappedMinutes)} h a tiempo libre',
].join();
