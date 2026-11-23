import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/day_kind.dart';
import '../../domain/money.dart';
import '../../domain/saved_hours.dart';
import '../../domain/workday.dart';
import '../components/info_button.dart';
import '../components/undo.dart';
import '../format.dart';
import '../money/money_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// «3,5» o «3.5» → 210 minutos. Nulo si no se entiende.
int? parseHours(String text) {
  final m = RegExp(r'^\s*(\d{1,3})(?:[.,](\d))?\s*$').firstMatch(text);
  if (m == null) return null;
  final tenths = int.parse(m[2] ?? '0');
  final minutes = int.parse(m[1]!) * 60 + tenths * 6;
  return minutes;
}

String _shortDate(DateTime d) =>
    '${d.day} ${monthName(d.month).substring(0, 3)} ${d.year}';

String _euros(int cents, bool hidden) => hidden ? '•••• €' : formatEuros(cents);

IconData _icon(SavedMoveKind k) => switch (k) {
  SavedMoveKind.before => Icons.history,
  SavedMoveKind.setAside => Icons.move_to_inbox_outlined,
  SavedMoveKind.timeOff => Icons.beach_access_outlined,
  SavedMoveKind.paid => Icons.payments_outlined,
  SavedMoveKind.swap => Icons.swap_horiz,
};

/// Qué hace cada movimiento, en una frase (RF-2).
String _explain(SavedMoveKind k) => switch (k) {
  SavedMoveKind.before =>
    'Horas que ya tenías guardadas antes de usar la app. No tocan ningún mes.',
  SavedMoveKind.setAside =>
    'Se restan de las horas normales del mes de la fecha: ese mes cobras '
        'menos y el cajón sube.',
  SavedMoveKind.timeOff =>
    'Horas que te devuelven como tiempo libre. Bajan del cajón.',
  SavedMoveKind.paid =>
    'Horas que te pagan en dinero, a la tarifa normal de la fecha. Bajan del '
        'cajón.',
  SavedMoveKind.swap =>
    'Se restan de las horas normales del mes de la fecha y te las dan como '
        'tiempo libre. No pasan por ningún cajón.',
};

/// Icono de cada cajón (009, RF-3).
IconData savedBoxIcon(SavedBox b) => switch (b) {
  SavedBox.company => Icons.business_outlined,
  SavedBox.own => Icons.savings_outlined,
};

/// Abre la ficha de [move] (o una nueva) y, si se borra, ofrece «Deshacer»
/// (008, RF-14, RF-15). Devuelve el aviso para que quien llama lo guarde.
/// [startKind] y [startDate] eligen de antemano el tipo y la fecha de uno
/// nuevo (022, RF-7).
Future<UndoHandle?> openSavedMove(
  BuildContext context,
  MoneyController money, [
  SavedMove? move,
  SavedMoveKind? startKind,
  DateTime? startDate,
]) async {
  final deleted = await Navigator.of(context).push<SavedMove>(
    MaterialPageRoute(
      builder: (_) => SavedMoveEditScreen(
        money: money,
        move: move,
        startKind: startKind,
        startDate: startDate,
      ),
    ),
  );
  if (deleted == null || !context.mounted) return null;
  return showUndo(
    context,
    message:
        'Borrado: ${deleted.kind.label}, ${formatMinutes(deleted.minutes)} h',
    onUndo: () => money.restoreSavedMove(deleted),
  );
}

/// Pestaña «Horas guardadas» de Extra (008, RF-13 a RF-17; 009, RF-2,
/// RF-3): una tarjeta por cajón, lo que ya salió y la lista de movimientos.
/// [onOpen] abre la ficha de un movimiento.
class SavedHoursView extends StatelessWidget {
  const SavedHoursView({super.key, required this.money, required this.onOpen});

  final MoneyController money;
  final void Function(SavedMove move) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = money.savedSummary;
    final hidden = money.hideAmounts;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.s,
        Space.gutter,
        Space.xxxl * 3, // que el botón «Añadir» no tape el último
      ),
      children: [
        for (final b in SavedBox.values) ...[
          _BoxCard(money: money, box: b),
          const SizedBox(height: Space.s),
        ],
        const SizedBox(height: Space.xs),
        Text(
          'Compensadas: ${formatMinutes(s.compensatedMinutes)} h · '
          'Cobradas: ${formatMinutes(s.paidMinutes)} h · '
          '${_euros(s.paidCents, hidden)}',
          style: AppText.body.copyWith(color: c.textSoft),
        ),
        if (money.saveFailed)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              'No se ha podido guardar el último cambio. Vuelve a intentarlo.',
              style: AppText.body.copyWith(color: c.error),
            ),
          ),
        const SizedBox(height: Space.l),
        if (money.savedMoves.isEmpty)
          Text(
            'Aún no hay movimientos. Toca «Añadir» y elige «Horas de antes» '
            'para meter lo que ya tenías guardado.',
            style: AppText.body.copyWith(color: c.textSoft),
          ),
        for (final m in money.savedMoves) _tile(context, m),
      ],
    );
  }

  Widget _tile(BuildContext context, SavedMove m) {
    final c = context.colors;
    final sign = m.kind.isIn ? '+' : '−';
    final note = m.note == null ? '' : ' · ${m.note}';
    final off = m.dayOff == null ? '' : ' · libre el ${_shortDate(m.dayOff!)}';
    final box = m.box;
    return ListTile(
      key: ValueKey('saved-${m.id}'),
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: Space.s,
      leading: Icon(
        box == null ? _icon(m.kind) : savedBoxIcon(box),
        color: c.bag.strong,
      ),
      title: Text(
        box == null ? m.kind.label : '${m.kind.label} · ${box.label}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppText.bodyStrong.copyWith(color: c.text),
      ),
      subtitle: Text(
        '${_shortDate(m.date)}$off$note'
        '${m.cents == null ? '' : ' · ${_euros(m.cents!, money.hideAmounts)}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppText.body.copyWith(color: c.textSoft),
      ),
      trailing: Text(
        '$sign${formatMinutes(m.minutes)} h',
        style: AppText.figure.copyWith(
          color: m.kind.isIn ? c.bag.strong : c.textSoft,
        ),
      ),
      onTap: () => onOpen(m),
    );
  }
}

/// Tarjeta de un cajón: la bolsa de empresa en violeta fuerte y mi reserva
/// en violeta suave, cada una con su icono (009, RF-3).
class _BoxCard extends StatelessWidget {
  const _BoxCard({required this.money, required this.box});

  final MoneyController money;
  final SavedBox box;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = money.savedSummary;
    final value = s.values[box];
    final strong = box == SavedBox.company;
    final bg = strong ? c.bag.strong : c.bag.soft;
    final fg = strong ? c.bag.onStrong : c.text;
    return Container(
      key: ValueKey('cajon-${box.name}'),
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      child: Row(
        children: [
          Icon(savedBoxIcon(box), color: fg, size: 28),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(box.label, style: AppText.label.copyWith(color: fg)),
                Text(
                  value == null
                      ? 'Falta la tarifa'
                      : _euros(value, money.hideAmounts),
                  style: AppText.body.copyWith(color: fg),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.s),
          Text(
            '${formatMinutes(s.balances[box]!)} h',
            style: AppText.figure.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

/// Ficha de un movimiento (RF-14, RF-15). Uno nuevo se guarda con «Añadir»;
/// uno que ya existe se guarda solo en cuanto es válido. Si se borra,
/// devuelve el movimiento borrado para poder deshacerlo.
class SavedMoveEditScreen extends StatefulWidget {
  const SavedMoveEditScreen({
    super.key,
    required this.money,
    this.move,
    this.startKind,
    this.startDate,
  });

  final MoneyController money;
  final SavedMove? move;

  /// Tipo y fecha con que empieza uno nuevo (022, RF-7).
  final SavedMoveKind? startKind;
  final DateTime? startDate;

  @override
  State<SavedMoveEditScreen> createState() => _SavedMoveEditScreenState();
}

class _SavedMoveEditScreenState extends State<SavedMoveEditScreen> {
  late SavedMove? _saved = widget.move;
  late SavedMoveKind _kind =
      widget.move?.kind ?? widget.startKind ?? SavedMoveKind.setAside;
  late SavedBox _box = widget.move?.box ?? SavedBox.own;
  late DateTime _date =
      widget.move?.date ?? _dateOnly(widget.startDate ?? widget.money.today);

  /// Día libre del cambio por libre (022, RF-8); se ignora en otro tipo.
  late DateTime? _dayOff = widget.move?.dayOff;
  late final _hours = TextEditingController(
    text: widget.move == null ? '' : formatMinutes(widget.move!.minutes),
  );
  late final _note = TextEditingController(text: widget.move?.note);
  bool _tried = false;
  bool _working = false;

  /// Lo que dijo el último intento de guardar (no cabe, falta la tarifa…).
  String? _refused;

  /// [_refused] viene de un cambio que aún no se ha guardado.
  bool _pendingChange = false;

  bool get _isNew => _saved == null;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void dispose() {
    _hours.dispose();
    _note.dispose();
    super.dispose();
  }

  SavedProblem? get _problem => validateSavedMove(
    minutes: parseHours(_hours.text),
    date: _date,
    today: widget.money.today,
    note: _note.text,
    dayOff: _offOrNull,
  );

  DateTime? get _offOrNull => _kind == SavedMoveKind.swap ? _dayOff : null;

  SavedMove _build() => SavedMove(
    id: _saved?.id,
    box: _kind.hasBox ? _box : null,
    kind: _kind,
    date: _date,
    minutes: parseHours(_hours.text)!,
    note: _note.text,
    cents: _kind == SavedMoveKind.paid ? 0 : null, // lo pone el controlador
    dayOff: _offOrNull,
  );

  /// Mismo movimiento, sin contar el importe (lo calcula el controlador).
  bool _same(SavedMove a, SavedMove? b) =>
      b != null &&
      a.kind == b.kind &&
      a.box == b.box &&
      a.date == b.date &&
      a.minutes == b.minutes &&
      a.note == b.note &&
      a.dayOff == b.dayOff;

  /// Al editar uno que ya existe, se guarda en cuanto es válido.
  Future<void> _changed() async {
    setState(() => _refused = null);
    if (_isNew || _problem != null) return;
    final move = _build();
    if (_same(move, _saved)) return;
    final refused = await widget.money.saveSavedMove(move, old: _saved);
    if (!mounted) return;
    setState(() {
      _refused = refused;
      _pendingChange = refused != null;
      if (refused == null) {
        _saved = widget.money.savedMoves.firstWhere((m) => m.id == move.id);
      }
    });
  }

  Future<void> _add() async {
    setState(() => _tried = true);
    if (_problem != null) return;
    setState(() => _working = true);
    final refused = await widget.money.saveSavedMove(_build());
    if (!mounted) return;
    setState(() {
      _working = false;
      _refused = refused;
      _pendingChange = false;
    });
    if (refused == null) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final move = _saved;
    if (move == null) return;
    final refused = await widget.money.deleteSavedMove(move);
    if (!mounted) return;
    if (refused == null) {
      Navigator.of(context).pop(move);
    } else {
      setState(() {
        _refused = refused;
        _pendingChange = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final today = _dateOnly(widget.money.today);
    final d = await showDatePicker(
      context: context,
      helpText: 'Fecha',
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: firstSavedDate,
      lastDate: today,
    );
    if (d == null) return;
    _date = d;
    await _changed();
  }

  /// Elegir el día libre (022, RF-8).
  Future<void> _pickDayOff() async {
    final today = widget.money.today;
    final last = lastDayOff(today);
    final start = _dayOff ?? _dateOnly(today);
    final d = await showDatePicker(
      context: context,
      helpText: 'Día libre',
      initialDate: start.isAfter(last) ? last : start,
      firstDate: firstSavedDate,
      lastDate: last,
    );
    if (d == null) return;
    _dayOff = d;
    await _changed();
  }

  /// «Se cobrarán a 15,00 €/h: 45,00 €» (RF-9).
  String? _paidPreview() {
    if (_kind != SavedMoveKind.paid) return null;
    final minutes = parseHours(_hours.text);
    final rate = rateFor(DayKind.normal, _date, widget.money.rates);
    if (rate == null) return 'Falta la tarifa normal en esa fecha.';
    if (minutes == null || _problem != null) return null;
    final hidden = widget.money.hideAmounts;
    return 'A ${_euros(rate.cents, hidden)}/h: '
        '${_euros(amountCents(minutes, rate.cents), hidden)}. El importe '
        'queda fijo aunque cambies la tarifa.';
  }

  /// Recordatorio de la jornada y botón «Día completo» (020, RF-1 a RF-3).
  List<Widget> _fullDay(AppColors c) {
    final minutes = workdayMinutes(_offOrNull ?? _date);
    return [
      const SizedBox(height: Space.s),
      Text(workdayReminder, style: AppText.body.copyWith(color: c.textSoft)),
      const SizedBox(height: Space.s),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey('dia-completo'),
          onPressed: minutes == 0
              ? null
              : () {
                  _hours.text = formatMinutes(minutes);
                  _changed();
                },
          icon: const Icon(Icons.wb_sunny_outlined),
          label: Text(
            minutes == 0
                ? 'Fin de semana: sin jornada'
                : 'Día completo · ${formatMinutes(minutes)} h',
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final problem = _problem;
    final showProblem = problem != null && (_tried || !_isNew);
    final preview = _paidPreview();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nuevo movimiento' : _kind.label),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Borrar',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.s,
          Space.gutter,
          Space.xxxl,
        ),
        children: [
          Text('Movimiento', style: AppText.label.copyWith(color: c.textSoft)),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final k in SavedMoveKind.values)
                ChoiceChip(
                  avatar: Icon(_icon(k), size: 18),
                  label: Text(k.label),
                  selected: _kind == k,
                  showCheckmark: false,
                  onSelected: (_) {
                    _kind = k;
                    _changed();
                  },
                ),
            ],
          ),
          const SizedBox(height: Space.s),
          Text(
            _explain(_kind),
            style: AppText.body.copyWith(color: c.textSoft),
          ),
          if (_kind.hasBox) ...[
            const SizedBox(height: Space.l),
            Text('Cajón', style: AppText.label.copyWith(color: c.textSoft)),
            const SizedBox(height: Space.s),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<SavedBox>(
                showSelectedIcon: false,
                segments: [
                  for (final b in SavedBox.values)
                    ButtonSegment(value: b, label: Text(b.label)),
                ],
                selected: {_box},
                onSelectionChanged: (v) {
                  _box = v.first;
                  _changed();
                },
              ),
            ),
          ],
          const SizedBox(height: Space.l),
          TextField(
            controller: _hours,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              LengthLimitingTextInputFormatter(5),
            ],
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(
              labelText: 'Horas',
              hintText: 'Por ejemplo, 3,5',
              suffixText: 'h',
            ),
          ),
          if (_kind == SavedMoveKind.timeOff || _kind == SavedMoveKind.swap)
            ..._fullDay(c),
          const SizedBox(height: Space.l),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event),
            label: Text(
              'Fecha: ${_date.day} de ${monthName(_date.month)} de ${_date.year}',
            ),
          ),
          if (_kind == SavedMoveKind.swap) ...[
            const SizedBox(height: Space.s),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('dia-libre'),
                    onPressed: _pickDayOff,
                    icon: const Icon(Icons.beach_access_outlined),
                    label: Text(
                      _dayOff == null
                          ? 'Día libre (opcional)'
                          : 'Día libre: ${_dayOff!.day} de '
                                '${monthName(_dayOff!.month)} de ${_dayOff!.year}',
                    ),
                  ),
                ),
                if (_dayOff != null)
                  IconButton(
                    tooltip: 'Quitar el día libre',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _dayOff = null;
                      _changed();
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.l),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [
              LengthLimitingTextInputFormatter(maxSavedNoteLength),
            ],
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(
              labelText: 'Nota (opcional)',
              hintText: 'Por ejemplo, Viernes libre',
            ),
          ),
          if (preview != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.m),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      preview,
                      style: AppText.body.copyWith(color: c.textSoft),
                    ),
                  ),
                  const InfoButton(
                    title: 'Cobrar horas guardadas',
                    text:
                        'Las horas guardadas se cobran siempre a la tarifa '
                        'normal que había el día del cobro. Ese importe se '
                        'guarda tal cual: si después cambias la tarifa, no '
                        'cambia.',
                  ),
                ],
              ),
            ),
          if (showProblem || _refused != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.m),
              child: Text(
                showProblem
                    ? (_isNew
                          ? problem.messageFor(widget.money.today)
                          : '${problem.messageFor(widget.money.today)} '
                                'Hasta entonces no se guarda.')
                    : (_pendingChange
                          ? '${_refused!} Hasta entonces no se guarda.'
                          : _refused!),
                style: AppText.body.copyWith(color: c.error),
              ),
            ),
          if (!_isNew) ...[
            const SizedBox(height: Space.l),
            Text(
              'Los cambios se guardan solos.',
              style: AppText.body.copyWith(color: c.textSoft),
            ),
          ] else ...[
            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: _working ? null : _add,
              child: const Text('Añadir'),
            ),
          ],
        ],
      ),
    );
  }
}
