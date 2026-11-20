import 'package:flutter/material.dart';

import '../../domain/day_entry.dart';
import '../../domain/day_kind.dart';
import '../../domain/money.dart';
import '../../domain/saved_hours.dart';
import '../components/confirm_dialog.dart';
import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'money_controller.dart';

/// Abre la pantalla de tarifas.
void openRates(BuildContext context, MoneyController money) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => RatesScreen(money: money)));

/// Fecha que se propone para la primera tarifa de un tipo.
final _beginning = DateTime(2020);

String _date(DateTime d) => '${d.day} de ${monthName(d.month)} de ${d.year}';

/// «1 ene 2026».
String _short(DateTime d) =>
    '${d.day} ${monthName(d.month).substring(0, 3)} ${d.year}';

DateTime _dayBefore(DateTime d) => DateTime(d.year, d.month, d.day - 1);

String _perHour(int cents) => '${formatEuros(cents)}/h';

String _kindName(DayKind kind) =>
    kind == DayKind.festive ? 'Festiva' : 'Normal';

/// El periodo de una tarifa dicho en una línea (021, RF-1).
String _periodText(RatePeriod p, DateTime today) {
  final end = p.end;
  if (end != null) return 'del ${_short(p.rate.start)} al ${_short(end)}';
  return p.rate.start.isAfter(today)
      ? 'desde el ${_short(p.rate.start)}'
      : 'desde el ${_short(p.rate.start)} · hasta hoy';
}

/// Ajustes → Tarifas: las tarifas de cada tipo como periodos (005, RF-1,
/// RF-2; 021).
class RatesScreen extends StatelessWidget {
  const RatesScreen({super.key, required this.money});
  final MoneyController money;

  /// Añade una tarifa ([old] nula) o cambia [old] (021, RF-3, RF-4).
  Future<void> _open(BuildContext context, DayKind kind, [Rate? old]) async {
    final result = await showDialog<_Result>(
      context: context,
      builder: (_) => _RateDialog(
        kind: kind,
        rates: [
          for (final r in money.rates)
            if (r.kind == kind) r,
        ],
        old: old,
        today: money.today,
      ),
    );
    if (result == null || !context.mounted) return;
    final start = result.start;
    if (start == null) {
      await _delete(context, old!);
      return;
    }
    final updated = Rate(kind, start, result.cents);
    final after = [
      for (final r in money.rates)
        if (old == null || !(r.kind == old.kind && r.start == old.start)) r,
      updated,
    ];
    // RF-6: un apartado sin precio dejaría de restar su importe.
    final blocked = setAsidesUnpricedBy(money.rates, after, money.savedMoves);
    if (blocked.isNotEmpty) {
      await _blocked(
        context,
        blocked,
        title: 'No se puede guardar',
        fix:
            'Elige una fecha de inicio que lo cubra o borra antes ese '
            'apartado.',
      );
      return;
    }
    if (old == null) {
      await money.saveRate(kind, result.cents, start);
    } else {
      await money.replaceRate(old, updated);
    }
  }

  Future<void> _blocked(
    BuildContext context,
    List<SavedMove> blocked, {
    required String title,
    required String fix,
  }) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(
        'El apartado del ${_date(blocked.first.date)}'
        '${blocked.length > 1 ? ' (y ${blocked.length - 1} más)' : ''} '
        'se quedaría sin precio. $fix',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );

  Future<void> _delete(BuildContext context, Rate r) async {
    // Un apartado sin precio dejaría de restar su importe (013, RF-15).
    final blocked = setAsidesLeftUnpriced(r, money.rates, money.savedMoves);
    if (blocked.isNotEmpty) {
      await _blocked(
        context,
        blocked,
        title: 'No se puede borrar',
        fix:
            'Borra antes ese apartado o añade otra tarifa normal que lo '
            'cubra.',
      );
      return;
    }
    final ok = await confirmDelete(
      context,
      title: 'Borrar tarifa',
      message:
          'Se borrará la tarifa de ${_perHour(r.cents)} desde el '
          '${_date(r.start)}. Sus días pasarán a la tarifa anterior, o '
          'quedarán sin tarifa si no hay.',
    );
    if (ok) await money.deleteRate(r);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Tarifas')),
      body: ListenableBuilder(
        listenable: money,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.s,
            Space.gutter,
            Space.xxxl,
          ),
          children: [
            Text(
              'Euros por hora de cada tipo. Cada tarifa vale desde su fecha '
              'hasta el día antes de la siguiente; la última, hasta hoy. '
              'Toca una para cambiarla o borrarla.',
              style: AppText.body.copyWith(color: c.textSoft),
            ),
            if (money.saveFailed)
              Padding(
                padding: const EdgeInsets.only(top: Space.s),
                child: Text(
                  'No se ha podido guardar el último cambio.',
                  style: AppText.body.copyWith(color: c.error),
                ),
              ),
            for (final kind in DayKind.values) ..._section(context, kind),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(BuildContext context, DayKind kind) {
    final c = context.colors;
    final periods = ratePeriods(money.rates, kind);
    final current = rateFor(kind, money.today, money.rates);
    final name = _kindName(kind);
    return [
      Padding(
        padding: const EdgeInsets.only(top: Space.xl, bottom: Space.xs),
        child: Semantics(header: true, child: Text(name, style: AppText.title)),
      ),
      Text(
        current == null ? 'Sin tarifa' : '${formatEuros(current.cents)} / hora',
        style: AppText.display.copyWith(
          color: kind == DayKind.festive ? c.festive.strong : c.normal.strong,
        ),
      ),
      for (final p in periods)
        Builder(
          builder: (context) => ListTile(
            key: ValueKey('tarifa-${kind.name}-${dateKey(p.rate.start)}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('${formatEuros(p.rate.cents)} / hora'),
            subtitle: Text(_periodText(p, money.today)),
            trailing: Icon(Icons.edit_outlined, color: c.textSoft),
            onTap: () => _open(context, kind, p.rate),
          ),
        ),
      const SizedBox(height: Space.s),
      Builder(
        builder: (context) => OutlinedButton(
          key: ValueKey('añadir-${kind.name}'),
          onPressed: () => _open(context, kind),
          child: Text(
            periods.isEmpty ? 'Poner tarifa $name' : 'Añadir tarifa nueva',
            semanticsLabel: periods.isEmpty
                ? null
                : 'Añadir tarifa ${name.toLowerCase()} nueva',
          ),
        ),
      ),
    ];
  }
}

/// Lo que se decide en la ficha: guardar ([start] con fecha) o borrar
/// ([start] nulo).
class _Result {
  const _Result(this.cents, DateTime this.start);
  const _Result.delete() : cents = 0, start = null;
  final int cents;
  final DateTime? start;
}

class _RateDialog extends StatefulWidget {
  const _RateDialog({
    required this.kind,
    required this.rates,
    required this.old,
    required this.today,
  });

  final DayKind kind;

  /// Las tarifas de ese tipo, incluida [old].
  final List<Rate> rates;

  /// La tarifa que se cambia; nula si es nueva.
  final Rate? old;
  final DateTime today;

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  late final _text = TextEditingController(
    text: switch (widget.old) {
      null => null,
      final o =>
        '${o.cents ~/ 100},${(o.cents % 100).toString().padLeft(2, '0')}',
    },
  );
  late DateTime _start =
      widget.old?.start ??
      (widget.rates.isEmpty
          ? _beginning
          : DateTime(widget.today.year, widget.today.month, widget.today.day));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int? get _cents {
    final c = parseEuros(_text.text);
    return c != null && c >= 1 && c <= maxRateCents ? c : null;
  }

  /// Las demás tarifas de ese tipo (sin la que se cambia).
  List<Rate> get _others => [
    for (final r in widget.rates)
      if (widget.old == null || r.start != widget.old!.start) r,
  ];

  /// RF-5: dos tarifas del mismo tipo no pueden empezar el mismo día.
  bool get _duplicate => _others.any((r) => r.start == _start);

  Future<void> _pick() async {
    final d = await showDatePicker(
      context: context,
      helpText: 'La tarifa vale desde',
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _start = d);
  }

  /// Cómo quedan las de alrededor (021, RF-4).
  List<String> get _notes {
    Rate? before;
    Rate? after;
    for (final r in _others) {
      if (r.start.isBefore(_start)) {
        if (before == null || r.start.isAfter(before.start)) before = r;
      } else if (r.start.isAfter(_start)) {
        if (after == null || r.start.isBefore(after.start)) after = r;
      }
    }
    return [
      if (before != null)
        'La de ${_perHour(before.cents)} terminará el '
            '${_short(_dayBefore(_start))}.'
      else if (_others.isNotEmpty)
        'Las horas de antes del ${_short(_start)} quedarán sin tarifa.',
      if (after != null)
        'Esta durará hasta el ${_short(_dayBefore(after.start))}, cuando '
            'empieza la de ${_perHour(after.cents)}.',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bad = _text.text.trim().isNotEmpty && _cents == null;
    final name = _kindName(widget.kind).toLowerCase();
    return AlertDialog(
      title: Text(widget.old == null ? 'Tarifa $name nueva' : 'Tarifa $name'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _text,
              autofocus: widget.old == null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Euros por hora',
                suffixText: '€/h',
                errorText: bad ? 'Escribe un importe, por ejemplo 15,50' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.m),
            OutlinedButton.icon(
              key: const ValueKey('fecha-tarifa'),
              onPressed: _pick,
              icon: const Icon(Icons.event),
              label: Text('Desde el ${_short(_start)}'),
            ),
            if (_duplicate)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  'Ya hay una tarifa que empieza ese día',
                  key: const ValueKey('tarifa-duplicada'),
                  style: AppText.body.copyWith(color: c.error),
                ),
              )
            else
              for (final n in _notes)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    n,
                    style: AppText.body.copyWith(color: c.textSoft),
                  ),
                ),
          ],
        ),
      ),
      actions: [
        if (widget.old != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(const _Result.delete()),
            child: Text('Borrar', style: TextStyle(color: c.error)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _cents == null || _duplicate
              ? null
              : () => Navigator.of(context).pop(_Result(_cents!, _start)),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
