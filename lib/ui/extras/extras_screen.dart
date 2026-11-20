import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/extras.dart';
import '../../domain/saved_hours.dart';
import '../components/motion_bits.dart';
import '../components/state_message.dart';
import '../components/undo.dart';
import '../format.dart';
import '../money/money_controller.dart';
import '../saved/saved_hours_view.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'extras_controller.dart';

/// «−100,00 €» o «+50,00 €»; con los importes ocultos, «−•••• €».
String signedEuros(int signedCents, {bool hidden = false}) {
  final sign = signedCents < 0 ? '−' : '+';
  return hidden ? '$sign•••• €' : '$sign${formatEuros(signedCents.abs())}';
}

String _shortDate(DateTime d) =>
    '${d.day} ${monthName(d.month).substring(0, 3)} ${d.year}';

IconData _icon(ExtraType t) => t == ExtraType.fine
    ? Icons.directions_car_outlined
    : Icons.add_card_outlined;

/// Las dos pestañas de Extra (009, RF-1).
enum ExtraTab { extras, saved }

/// Sección «Extra»: multas y extras, aparte de las horas (007, RF-1 a RF-8),
/// y, si hay, las horas guardadas en su propia pestaña (009, RF-1 a RF-3).
class ExtrasScreen extends StatefulWidget {
  const ExtrasScreen({
    super.key,
    required this.extras,
    this.money,
    this.actions = const [],
    this.tab,
  });

  /// La pestaña elegida; la comparte la app para que Resumen pueda abrir
  /// «Horas guardadas» (009, RF-4). Si es nula, se usa una propia.
  final ValueNotifier<ExtraTab>? tab;

  final ExtrasController extras;

  /// De aquí sale la preferencia de ocultar importes (RF-8).
  final MoneyController? money;

  /// Botones extra de la barra de título (el engranaje de Ajustes).
  final List<Widget> actions;

  @override
  State<ExtrasScreen> createState() => _ExtrasScreenState();
}

class _ExtrasScreenState extends State<ExtrasScreen> {
  UndoHandle? _undo;
  late final ValueNotifier<ExtraTab> _tab =
      widget.tab ?? ValueNotifier(ExtraTab.extras);

  bool get _hidden => widget.money?.hideAmounts ?? false;

  bool get _hasSaved => widget.money?.hasSavedHours ?? false;

  bool get _onSaved => _hasSaved && _tab.value == ExtraTab.saved;

  /// Las dos pestañas, para pasar de una a otra deslizando (009, RF-1).
  late final PageController _pages = PageController(
    initialPage: _tab.value.index,
  );

  @override
  void initState() {
    super.initState();
    _tab.addListener(_showTab);
  }

  @override
  void dispose() {
    _undo?.dismiss();
    _tab.removeListener(_showTab);
    if (widget.tab == null) _tab.dispose();
    _pages.dispose();
    super.dispose();
  }

  /// Lleva las páginas a la pestaña elegida con el selector o desde Resumen.
  void _showTab() {
    _undo?.dismiss();
    if (!_pages.hasClients) return;
    final target = _tab.value.index;
    if (_pages.page?.round() == target) return;
    final duration = context.motion(Motion.medium);
    if (duration == Duration.zero) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(target, duration: duration, curve: Curves.easeOut);
    }
  }

  Future<void> _openSaved([SavedMove? move]) async {
    _undo?.dismiss();
    _undo = await openSavedMove(context, widget.money!, move);
  }

  Future<void> _open([ExtraItem? item]) async {
    _undo?.dismiss();
    final deleted = await Navigator.of(context).push<ExtraItem>(
      MaterialPageRoute(
        builder: (_) => ExtraEditScreen(extras: widget.extras, item: item),
      ),
    );
    if (deleted == null || !mounted) return;
    _undo = showUndo(
      context,
      message: '${extraTypeName(deleted.type)} borrada: ${deleted.concept}'
          .replaceFirst('Extra borrada', 'Extra borrado'),
      onUndo: () => widget.extras.restore(deleted),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _tab,
      builder: (context, _) => _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    final money = widget.money;
    return Scaffold(
      appBar: AppBar(
        title: Text(_hasSaved ? 'Extra' : 'Multas y extras'),
        actions: [
          if (money != null)
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
          ...widget.actions,
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _onSaved ? _openSaved() : _open(),
        icon: const Icon(Icons.add),
        label: const Text('Añadir'),
      ),
      body: Column(
        children: [
          if (_hasSaved)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.s,
                Space.gutter,
                Space.s,
              ),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ExtraTab>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ExtraTab.extras,
                      label: Text('Multas y extras'),
                    ),
                    ButtonSegment(
                      value: ExtraTab.saved,
                      label: Text('Horas guardadas'),
                    ),
                  ],
                  selected: {_tab.value},
                  onSelectionChanged: (v) => _tab.value = v.first,
                ),
              ),
            ),
          Expanded(
            child: _hasSaved
                ? PageView(
                    controller: _pages,
                    onPageChanged: (i) => _tab.value = ExtraTab.values[i],
                    children: [_extrasContent(context), _savedContent()],
                  )
                : _extrasContent(context),
          ),
        ],
      ),
    );
  }

  Widget _savedContent() {
    final money = widget.money!;
    return ListenableBuilder(
      listenable: money,
      builder: (context, _) => SavedHoursView(money: money, onOpen: _openSaved),
    );
  }

  Widget _extrasContent(BuildContext context) {
    final money = widget.money;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.extras, ?money]),
      builder: (context, _) => switch (widget.extras.status) {
        ExtrasStatus.loading => const Center(
          child: StateMessage.loading(message: 'Abriendo…'),
        ),
        ExtrasStatus.error => Center(
          child: StateMessage.error(
            title: 'No se pueden abrir las multas y extras',
            message:
                'No se ha borrado nada. Vuelve a intentarlo; si sigue '
                'fallando, reinicia la app.',
            actionLabel: 'Reintentar',
            onAction: widget.extras.load,
          ),
        ),
        ExtrasStatus.ready => _list(context),
      },
    );
  }

  Widget _list(BuildContext context) {
    final c = context.colors;
    final x = widget.extras;
    final t = x.totals;
    final firsts = firstFinesOfYear(x.items);
    Widget total(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.label.copyWith(color: c.textSoft)),
          Text(value, style: AppText.figure.copyWith(color: color)),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.s,
        Space.gutter,
        Space.xxxl * 3, // que el botón «Añadir» no tape el último
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            total(
              'Extras pendientes',
              signedEuros(t.pendingBonusCents, hidden: _hidden),
              c.normal.strong,
            ),
            const SizedBox(width: Space.l),
            total(
              'Multas pendientes',
              signedEuros(-t.pendingFineCents, hidden: _hidden),
              c.error,
            ),
          ],
        ),
        if (x.saveFailed)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              'No se ha podido guardar el último cambio. Vuelve a intentarlo.',
              style: AppText.body.copyWith(color: c.error),
            ),
          ),
        const SizedBox(height: Space.l),
        if (x.items.isEmpty)
          Text(
            'Aún no hay multas ni extras. Toca «Añadir» para apuntar uno.',
            style: AppText.body.copyWith(color: c.textSoft),
          ),
        for (final e in x.items) _tile(context, e, firsts.contains(e.id)),
      ],
    );
  }

  Widget _tile(BuildContext context, ExtraItem e, bool firstOfYear) {
    final c = context.colors;
    // Marcas de la multa (019, RF-2 a RF-4).
    final tags = [
      if (firstOfYear) 'Primera del año',
      if (e.earlyPayment) 'Pronto pago',
      if (e.companyPays) 'La paga la empresa',
    ];
    final discounted = e.dueCents != e.cents;
    final color = !e.isPending
        ? c.textSoft
        : e.type == ExtraType.fine
        ? c.error
        : c.normal.strong;
    return ListTile(
      key: ValueKey('extra-${e.id}'),
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: Space.s,
      leading: Icon(_icon(e.type), color: c.textSoft),
      title: Text(
        e.concept,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppText.bodyStrong.copyWith(
          color: e.isPending ? c.text : c.textSoft,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_shortDate(e.date)} · ${extraStatusName(e.type, e.status)}',
            style: AppText.body.copyWith(color: c.textSoft),
          ),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final t in tags)
                    _Tag(t, key: ValueKey('marca-$t-${e.id}')),
                ],
              ),
            ),
        ],
      ),
      trailing: FadeSwap(
        value: (discounted, e.companyPays, e.signedCents, _hidden),
        alignment: Alignment.centerRight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // El importe completo tachado y debajo lo que cuenta (RF-2).
            if (discounted)
              Text(
                signedEuros(-e.cents, hidden: _hidden),
                key: ValueKey('tachado-${e.id}'),
                style: AppText.label.copyWith(
                  color: c.textSoft,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            if (!e.companyPays)
              Text(
                signedEuros(e.signedCents, hidden: _hidden),
                style: AppText.figure.copyWith(color: color),
              ),
          ],
        ),
      ),
      onTap: () => _open(e),
    );
  }
}

/// Una marca pequeña de la lista: «Primera del año», «Pronto pago»…
class _Tag extends StatelessWidget {
  const _Tag(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 2),
      decoration: BoxDecoration(
        color: c.normal.soft,
        borderRadius: BorderRadius.circular(Radii.tiny),
      ),
      child: Text(text, style: AppText.caption.copyWith(color: c.text)),
    );
  }
}

/// Ficha de una multa o un extra (RF-2 a RF-5). Uno nuevo se guarda con
/// «Añadir»; uno que ya existe se guarda solo en cuanto lo escrito es válido.
/// Si se borra, devuelve el apunte borrado para poder deshacerlo.
class ExtraEditScreen extends StatefulWidget {
  const ExtraEditScreen({super.key, required this.extras, this.item});

  final ExtrasController extras;
  final ExtraItem? item;

  @override
  State<ExtraEditScreen> createState() => _ExtraEditScreenState();
}

class _ExtraEditScreenState extends State<ExtraEditScreen> {
  late ExtraItem? _saved = widget.item;
  late ExtraType _type = widget.item?.type ?? ExtraType.fine;
  late DateTime _date = widget.item?.date ?? widget.extras.today;
  late ExtraStatus _status = widget.item?.status ?? ExtraStatus.pending;
  late DateTime? _closedOn = widget.item?.closedOn;
  late bool _early = widget.item?.earlyPayment ?? false;
  late bool _company = widget.item?.companyPays ?? false;
  late final _amount = TextEditingController(
    text: widget.item == null ? '' : _plain(widget.item!.cents),
  );
  late final _concept = TextEditingController(text: widget.item?.concept);
  bool _tried = false;
  bool _working = false;

  bool get _isNew => _saved == null;

  static String _plain(int cents) =>
      formatEuros(cents).replaceAll(' €', '').replaceAll('.', '');

  @override
  void dispose() {
    _amount.dispose();
    _concept.dispose();
    super.dispose();
  }

  ExtraProblem? get _problem => validateExtra(
    cents: parseEuros(_amount.text),
    concept: _concept.text,
    date: _date,
    today: widget.extras.today,
  );

  ExtraItem _build() => ExtraItem(
    id: _saved?.id,
    type: _type,
    date: _date,
    cents: parseEuros(_amount.text)!,
    concept: _concept.text,
    status: _status,
    closedOn: _status == ExtraStatus.closed ? _closedOn : null,
    earlyPayment: _type == ExtraType.fine && _early,
    companyPays: _type == ExtraType.fine && _company,
  );

  /// Al editar uno que ya existe, se guarda en cuanto es válido.
  Future<void> _changed() async {
    setState(() {});
    if (_isNew || _problem != null) return;
    final item = _build();
    if (item == _saved) return;
    _saved = item;
    await widget.extras.save(item);
  }

  Future<void> _add() async {
    setState(() => _tried = true);
    if (_problem != null) return;
    setState(() => _working = true);
    final saved = await widget.extras.save(_build());
    if (!mounted) return;
    setState(() => _working = false);
    if (saved != null) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final item = _saved;
    if (item == null) return;
    // Si no se ha podido borrar, la ficha se queda abierta y lo dice.
    if (await widget.extras.delete(item) && mounted) {
      Navigator.of(context).pop(item);
    }
  }

  Future<void> _pickDate() async {
    final today = widget.extras.today;
    final d = await showDatePicker(
      context: context,
      helpText: 'Fecha',
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: firstExtraDate,
      lastDate: today,
    );
    if (d == null) return;
    _date = d;
    await _changed();
  }

  Future<void> _pickStatus(ExtraStatus s) async {
    if (s == ExtraStatus.closed) {
      final today = widget.extras.today;
      final d = await showDatePicker(
        context: context,
        helpText: _type == ExtraType.fine
            ? 'Fecha del descuento'
            : 'Fecha del cobro',
        initialDate: today,
        firstDate: firstExtraDate,
        lastDate: DateTime(today.year + 1, 12, 31),
      );
      if (d == null) return;
      _closedOn = d;
    }
    _status = s;
    await _changed();
  }

  /// «Cuenta 75,00 €» con pronto pago y un importe válido.
  String _earlyHint() {
    final cents = parseEuros(_amount.text);
    if (!_early || cents == null || cents < 1 || cents > maxExtraCents) {
      return 'Pagada en plazo: cuenta la mitad.';
    }
    return 'Cuenta ${formatEuros((cents + 1) ~/ 2)}.';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final problem = _problem;
    final showProblem = problem != null && (_tried || !_isNew);
    final fine = _type == ExtraType.fine;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nuevo apunte' : (fine ? 'Multa' : 'Extra')),
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
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ExtraType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ExtraType.fine,
                  label: Text('Multa'),
                  icon: Icon(Icons.directions_car_outlined),
                ),
                ButtonSegment(
                  value: ExtraType.bonus,
                  label: Text('Extra'),
                  icon: Icon(Icons.add_card_outlined),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (v) {
                _type = v.first;
                _changed();
              },
            ),
          ),
          const SizedBox(height: Space.s),
          Text(
            fine
                ? 'Una multa resta: es dinero que en teoría debes a la empresa.'
                : 'Un extra suma: es dinero que la empresa te debe aparte de '
                      'las horas.',
            style: AppText.body.copyWith(color: c.textSoft),
          ),
          const SizedBox(height: Space.l),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              LengthLimitingTextInputFormatter(9),
            ],
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(
              labelText: 'Importe',
              suffixText: '€',
            ),
          ),
          const SizedBox(height: Space.l),
          TextField(
            controller: _concept,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [
              LengthLimitingTextInputFormatter(maxConceptLength),
            ],
            onChanged: (_) => _changed(),
            decoration: InputDecoration(
              labelText: 'Concepto',
              hintText: fine
                  ? 'Por ejemplo, Multa velocidad A-67'
                  : 'Por ejemplo, Dieta viaje a Bilbao',
            ),
          ),
          const SizedBox(height: Space.l),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event),
            label: Text(
              'Fecha: ${_date.day} de ${monthName(_date.month)} de ${_date.year}',
            ),
          ),
          // Solo multas; se cambian mientras está pendiente (019, RF-1, RF-5).
          if (fine) ...[
            const SizedBox(height: Space.m),
            SwitchListTile(
              key: const ValueKey('pronto-pago'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Pronto pago (−50 %)'),
              subtitle: FadeSwap(
                value: _earlyHint(),
                child: Text(
                  _earlyHint(),
                  style: AppText.body.copyWith(color: c.textSoft),
                ),
              ),
              value: _early,
              onChanged: _status == ExtraStatus.pending
                  ? (v) {
                      _early = v;
                      _changed();
                    }
                  : null,
            ),
            SwitchListTile(
              key: const ValueKey('paga-empresa'),
              contentPadding: EdgeInsets.zero,
              title: const Text('La paga la empresa'),
              subtitle: Text(
                'Entonces no resta. Enciéndelo solo cuando lo confirmes.',
                style: AppText.body.copyWith(color: c.textSoft),
              ),
              value: _company,
              onChanged: _status == ExtraStatus.pending
                  ? (v) {
                      _company = v;
                      _changed();
                    }
                  : null,
            ),
          ],
          if (showProblem)
            Padding(
              padding: const EdgeInsets.only(top: Space.m),
              child: Text(
                _isNew
                    ? problem.message
                    : '${problem.message} Hasta entonces no se guarda.',
                style: AppText.body.copyWith(color: c.error),
              ),
            ),
          ListenableBuilder(
            listenable: widget.extras,
            builder: (context, _) => widget.extras.saveFailed
                ? Padding(
                    padding: const EdgeInsets.only(top: Space.m),
                    child: Text(
                      'No se ha podido guardar el último cambio. Vuelve a '
                      'intentarlo.',
                      style: AppText.body.copyWith(color: c.error),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (!_isNew) ...[
            const SizedBox(height: Space.xl),
            Text('Estado', style: AppText.label.copyWith(color: c.textSoft)),
            const SizedBox(height: Space.s),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ExtraStatus>(
                showSelectedIcon: false,
                segments: [
                  for (final s in ExtraStatus.values)
                    ButtonSegment(
                      value: s,
                      label: Text(extraStatusName(_type, s)),
                    ),
                ],
                selected: {_status},
                onSelectionChanged: (v) {
                  if (v.first != _status) _pickStatus(v.first);
                },
              ),
            ),
            if (_status == ExtraStatus.closed && _closedOn != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.s),
                child: Text(
                  '${extraStatusName(_type, _status)} el '
                  '${_shortDate(_closedOn!)}',
                  style: AppText.body.copyWith(color: c.textSoft),
                ),
              ),
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
