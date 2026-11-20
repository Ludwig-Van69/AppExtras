import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/day_entry_repository.dart';
import '../../domain/day_kind.dart';
import '../../domain/hour_options.dart';
import '../../domain/money.dart';
import '../../domain/saved_hours.dart';
import '../backup/backup_controller.dart';
import '../backup/backup_notice.dart';
import '../backup/backup_screen.dart';
import '../holidays/holidays_controller.dart';
import '../money/money_controller.dart';
import '../settings/settings_screen.dart';
import '../components/big_hours.dart';
import '../components/day_heading.dart';
import '../components/day_selector.dart';
import '../components/haptics.dart';
import '../components/hour_preset_button.dart';
import '../components/info_button.dart';
import '../components/saved_mark.dart';
import '../components/state_message.dart';
import '../components/summary_figure.dart';
import '../components/tide.dart';
import '../components/undo.dart';
import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../vacation/vacation_controller.dart';
import 'day_picker_sheet.dart';
import 'log_controller.dart';
import 'other_hours_dialog.dart';
import 'reason_field.dart';

/// Una jornada completa llena el agua, sea normal o festiva (001, RF-11).
const _fullTideMinutes = 480;

const _saveFailedMessage =
    'No se ha podido guardar. Vuelve a intentarlo; si sigue fallando, '
    'reinicia la app.';
const _readFailedMessage =
    'No se han podido leer los datos de ese día. Vuelve a intentarlo.';

DataKind _dataKind(DayKind k) =>
    k == DayKind.festive ? DataKind.festive : DataKind.normal;

String _kindName(DayKind k) => k == DayKind.festive ? 'Festiva' : 'Normal';

/// La pantalla de apuntar horas: la que se abre al arrancar (RF-1).
class LogScreen extends StatefulWidget {
  const LogScreen({
    super.key,
    required this.repository,
    this.settingsButton,
    this.clock,
    this.backup,
    this.holidays,
    this.saves,
    this.money,
    this.savedMoves,
    this.vacation,
  });

  final DayEntryRepository repository;

  /// El engranaje que abre Ajustes, junto a la fecha (007, RF-16).
  final Widget? settingsButton;

  /// Las copias; si es nulo, la pantalla funciona sin avisos ni copias.
  final BackupService? backup;

  /// Los festivos; si es nulo, solo los fines de semana se proponen festivos.
  final HolidaysController? holidays;

  /// Para que otras pantallas esperen a que termine de guardar.
  final SaveWaiter? saves;

  /// El dinero; se recalcula al guardar o borrar un día.
  final MoneyController? money;

  /// Reloj para los tests; si es nulo, la hora real.
  final DateTime Function()? clock;

  /// Las horas guardadas, para no bajar un mes por debajo de lo apartado
  /// (008, RF-8). Si es nulo, no se comprueba.
  final Future<List<SavedMove>> Function()? savedMoves;

  /// Las vacaciones, para señalar los días de vacaciones (010, RF-17).
  final VacationController? vacation;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> with WidgetsBindingObserver {
  late final LogController _c;
  UndoHandle? _undo;
  DateTime _shownDate = DateTime(0);

  /// Apuntes hechos: cada uno nuevo enseña «✓ Apuntado» (012, RF-5).
  int _saves = 0;
  bool _towardsPast = true;

  /// Cifra marcada a la espera del segundo toque, y si es para borrar
  /// (013, RF-1 a RF-4). Se quita sola en [_armTimeout].
  int? _armed;
  bool _armedDelete = false;
  Timer? _armTimer;
  static const _armTimeout = Duration(seconds: 3);

  /// Velocidad mínima (píxeles por segundo) para que un deslizamiento cambie
  /// de día; por debajo se toma como un roce.
  static const _swipeMinVelocity = 300.0;

  @override
  void initState() {
    super.initState();
    _c =
        LogController(
            widget.repository,
            clock: widget.clock,
            calendar: widget.holidays == null
                ? null
                : () => widget.holidays!.calendar,
            savedMoves: widget.savedMoves,
          )
          ..onSaveFailed = (() {
            _saves = 0; // si no se guardó, la marca no debe seguir
            _message(_saveFailedMessage);
          })
          ..onSetAsideBlocked = ((text) {
            _saves = 0; // no se guardó: fuera la marca (012, RF-5)
            _message(text);
          })
          ..isImportedMonth = widget.money?.isImportedMonth
          ..onReadFailed = (() => _message(_readFailedMessage))
          ..onDataChanged = (() {
            widget.backup?.markChanged();
            widget.money?.refresh();
          })
          ..addListener(_changed)
          ..load();
    widget.saves?.attach(() => _c.idle);
    _restoredSeen = widget.backup?.restoredCount ?? 0;
    widget.backup?.addListener(_backupChanged);
    widget.holidays?.addListener(_changed);
    widget.money?.addListener(_moneyChanged);
    widget.vacation?.addListener(_moneyChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  late int _restoredSeen;

  /// Tras restaurar una copia, se vuelve a leer todo y se muestra hoy (RF-14).
  void _backupChanged() {
    final n = widget.backup!.restoredCount;
    if (n != _restoredSeen) {
      _restoredSeen = n;
      _c.load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _c.refreshToday(); // RF-5
    if (state == AppLifecycleState.paused) {
      _disarm();
      _backUpOnLeaving(); // RF-4
    }
  }

  /// Al salir de la app, termina de guardar lo pendiente y hace la copia si
  /// hay cambios.
  Future<void> _backUpOnLeaving() async {
    final backup = widget.backup;
    if (backup == null) return;
    await _c.idle;
    await backup.onLeavingApp();
  }

  void _openBackups() {
    final backup = widget.backup;
    if (backup == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BackupScreen(
          backup: backup,
          waitForSaves: () => _c.idle,
          clock: widget.clock,
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.backup?.removeListener(_backupChanged);
    widget.holidays?.removeListener(_changed);
    widget.money?.removeListener(_moneyChanged);
    widget.vacation?.removeListener(_moneyChanged);
    widget.saves?.attach(null);
    WidgetsBinding.instance.removeObserver(this);
    _undo?.dismiss(); // el aviso no sobrevive a la pantalla
    _armTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// El dinero solo cambia la línea del mes: no toca el aviso de Deshacer.
  void _moneyChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    // Cualquier otro cambio quita el aviso de Deshacer (RF-20).
    if (!_c.canUndo) {
      _undo?.dismiss();
      _undo = null;
    }
    final d = _c.selectedDate;
    if (d != _shownDate) {
      _towardsPast = d.isBefore(_shownDate);
      _shownDate = d;
      _disarm(rebuild: false); // otro día: fuera la marca (013, RF-4)
      _saves = 0; // y fuera «✓ Apuntado» (013, RF-13)
    }
    setState(() {});
  }

  void _message(String text) {
    if (!mounted) return;
    _undo = null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _selectOption(int option) async {
    final today = _c.today;
    if (option < 3) {
      await _c.selectDate(
        DateTime(today.year, today.month, today.day - option),
      );
      return;
    }
    final picked = await showDayPickerSheet(
      context,
      selected: _c.selectedDate,
      today: today,
      firstMonth: _c.firstSelectableDate,
      loadMonth: _c.monthEntries,
      vacationOn: widget.vacation?.dayOn,
      isDayOff: (d) =>
          d.weekday > DateTime.friday ||
          widget.holidays?.calendar.holidayOn(d) != null,
    );
    if (picked != null) await _c.selectDate(picked);
  }

  /// Mover el dedo hacia la izquierda va al pasado y hacia la derecha vuelve
  /// hacia Hoy, solo entre Hoy, Ayer y Anteayer (006, RF-4).
  ///
  /// Se mira el dedo directamente (sin competir con otros gestos), para que
  /// funcione también si empieza sobre el campo del motivo (013, RF-17).
  void _pointerDown(PointerDownEvent e) {
    _swipeStart ??= (e.pointer, e.position, e.timeStamp);
  }

  void _pointerUp(PointerUpEvent e) {
    final start = _swipeStart;
    if (start == null || start.$1 != e.pointer) return;
    _swipeStart = null;
    final d = e.position - start.$2;
    final ms = (e.timeStamp - start.$3).inMicroseconds / 1e6;
    if (d.dx.abs() < _swipeMinDistance || d.dx.abs() < 2 * d.dy.abs()) return;
    if (ms <= 0 || d.dx.abs() / ms < _swipeMinVelocity) return;
    _swipe(d.dx);
  }

  void _pointerCancel(PointerCancelEvent e) {
    if (_swipeStart?.$1 == e.pointer) _swipeStart = null;
  }

  (int, Offset, Duration)? _swipeStart;
  static const _swipeMinDistance = 60.0;

  void _swipe(double v) {
    final option = _c.dayOption.index;
    if (option > 2) return; // «Otro día»
    final next = option + (v < 0 ? 1 : -1);
    if (next < 0 || next > 2) return;
    _selectOption(next);
  }

  /// Primer toque: marca la cifra; segundo toque sobre la misma: apunta o
  /// borra (013, RF-1 a RF-4).
  void _presetTapped(int m, {required bool isSelected}) {
    if (_armed == m && _armedDelete == isSelected) {
      _disarm();
      isSelected ? _delete() : _save(m);
      return;
    }
    _armTimer?.cancel();
    _armTimer = Timer(_armTimeout, _disarm);
    setState(() {
      _armed = m;
      _armedDelete = isSelected;
    });
  }

  void _disarm({bool rebuild = true}) {
    _armTimer?.cancel();
    _armTimer = null;
    if (_armed == null) return;
    _armed = null;
    _armedDelete = false;
    if (rebuild && mounted) setState(() {});
  }

  /// Apunta [m] horas y lo confirma con la marca (012, RF-5).
  void _save(int m) {
    if (m == _c.selectedMinutes) return;
    _c.setMinutes(m);
    setState(() => _saves++);
  }

  void _delete() {
    final deleted = _c.deleteSelected();
    if (deleted == null) return;
    Haptics.delete();
    final day = dayPhrase(deleted.date, today: _c.today);
    _undo = showUndo(
      context,
      message: '${formatMinutes(deleted.minutes)} h borradas de $day'
          .replaceFirst(' de el ', ' del '),
      onUndo: _c.undoDelete,
    );
  }

  Future<void> _other() async {
    _disarm();
    final picked = await showOtherHoursDialog(
      context,
      currentMinutes: _c.selectedMinutes,
      kind: _dataKind(_c.selectedKind),
    );
    if (picked == null || !mounted) return;
    if (picked == 0) {
      _delete();
    } else if (picked != _c.selectedMinutes) {
      Haptics.tap();
      _save(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_c.status) {
        LogStatus.loading => const Center(
          child: StateMessage.loading(message: 'Abriendo tus horas…'),
        ),
        LogStatus.error => Center(
          child: StateMessage.error(
            title: 'No se pueden abrir tus datos',
            message:
                'No se ha borrado nada. Vuelve a intentarlo; si sigue '
                'fallando, reinicia la app.',
            actionLabel: 'Reintentar',
            onAction: _c.load,
          ),
        ),
        LogStatus.ready => _ready(context),
      },
    );
  }

  /// «A cobrar este mes: 105,00 €» del mes del día elegido, ya restado lo
  /// apartado (009, RF-6 a RF-8).
  Widget _monthMoney(BuildContext context) {
    final c = context.colors;
    final money = widget.money!;
    final month = YearMonth.of(_c.selectedDate);
    MonthLine? line;
    for (final m in money.overview.months) {
      if (m.month == month) line = m;
    }
    final paid = line?.status == MonthStatus.paid;
    final cents = line?.amountCents ?? 0;
    final amount = money.hideAmounts ? '•••• €' : formatEuros(cents);
    final missing = line != null && !line.isComplete ? ' (falta tarifa)' : '';
    final label = '${paid ? 'Cobrado' : 'A cobrar'} este mes';
    // Va en el hueco de debajo de los botones (012, RF-6). El aviso de
    // Deshacer lo tapa unos segundos: es temporal.
    return Semantics(
      key: const ValueKey('dinero-del-mes'),
      label: '$label: $amount$missing',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.l,
          vertical: Space.s,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.medium),
          border: Border.all(color: c.outline),
        ),
        child: Row(
          children: [
            Icon(
              paid ? Icons.check_circle_outline : Icons.euro,
              size: 20,
              color: c.textSoft,
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(
                label + missing,
                maxLines: 2,
                style: AppText.label.copyWith(color: c.textSoft),
              ),
            ),
            const SizedBox(width: Space.s),
            Text(amount, style: AppText.bodyStrong.copyWith(color: c.text)),
          ],
        ),
      ),
    );
  }

  /// «Toca otra vez para apuntar» o «… para borrar» (013, RF-1, RF-3).
  Widget _armHint(BuildContext context) {
    final c = context.colors;
    final color = _armedDelete
        ? c.festive.strong
        : c.of(_dataKind(_c.selectedKind)).strong;
    return Semantics(
      liveRegion: true,
      child: Padding(
        key: const ValueKey('aviso-doble-toque'),
        padding: const EdgeInsets.symmetric(vertical: Space.s),
        child: Text(
          _armedDelete
              ? 'Toca otra vez para borrar'
              : 'Toca otra vez para apuntar',
          textAlign: TextAlign.center,
          style: AppText.bodyStrong.copyWith(color: color),
        ),
      ),
    );
  }

  Widget _ready(BuildContext context) {
    final c = context.colors;
    final kind = _c.selectedKind;
    final dataKind = _dataKind(kind);
    final minutes = _c.selectedMinutes;
    final summary = _c.monthSummary;

    final top = Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.l,
        Space.gutter,
        Space.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DaySelector(
            selected: _c.dayOption.index,
            labels: const ['Hoy', 'Ayer', 'Anteayer', 'Otro día'],
            onChanged: _selectOption,
          ),
          const SizedBox(height: Space.l),
          Row(
            children: [
              Expanded(
                child: DayHeading(
                  text: formatLongDate(_c.selectedDate, today: _c.today),
                  towardsPast: _towardsPast,
                ),
              ),
              ?widget.settingsButton,
            ],
          ),
          if (widget.vacation?.dayOn(_c.selectedDate) != null)
            Row(
              key: const ValueKey('dia-de-vacaciones'),
              children: [
                Icon(Icons.beach_access, size: 18, color: c.vacation.strong),
                const SizedBox(width: Space.xs),
                Text(
                  widget.vacation!.dayOn(_c.selectedDate)!.half
                      ? 'Vacaciones (medio día)'
                      : 'Vacaciones',
                  style: AppText.label.copyWith(color: c.vacation.strong),
                ),
              ],
            ),
          // Sin papelera: se borra volviendo a tocar el botón resaltado
          // (012, RF-2, RF-4).
          BigHours(minutes: minutes),
          const SizedBox(height: Space.s),
          Row(
            children: [
              Semantics(
                hint: 'Toca para cambiar el tipo de hora',
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.of(dataKind).strong,
                    foregroundColor: c.of(dataKind).onStrong,
                  ),
                  onPressed: _c.toggleKind,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(_kindName(kind)),
                ),
              ),
              if (_c.selectedHoliday != null)
                Expanded(
                  child: Text(
                    'Festivo: ${_c.selectedHoliday!.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(color: c.text),
                  ),
                ),
              const InfoButton(
                title: 'Normal o festiva',
                text:
                    'Los sábados y domingos se proponen como festivos. Si un '
                    'día es festivo por otro motivo, tócalo para cambiarlo.',
              ),
            ],
          ),
          const SizedBox(height: Space.l),
          ReasonField(
            date: _c.selectedDate,
            reason: _c.selectedReason,
            enabled: _c.canEditReason,
            suggestionsFor: _c.suggestionsFor,
            onSave: (date, text) => _c.setReason(text, date: date),
          ),
          if (widget.backup != null)
            BackupNotice(backup: widget.backup!, onReview: _openBackups),
        ],
      ),
    );

    // Lo que se toca con el pulgar va abajo, sobre una hoja que flota en
    // el agua.
    final bottom = AnimatedContainer(
      duration: context.motion(Motion.theme),
      color: c.of(dataKind).soft,
      child: Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.sheet),
          ),
        ),
        // Abajo se reserva el hueco del aviso, para que no tape los botones;
        // si hay dinero, ese hueco lo ocupa la línea de «A cobrar».
        padding: EdgeInsets.fromLTRB(
          Space.gutter,
          Space.xl,
          Space.gutter,
          widget.money == null ? Sizes.undoReserve : Space.s,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SummaryRow(
              children: [
                SummaryFigure(
                  label: 'Este mes',
                  value: '${formatMinutes(summary.totalMinutes)} h',
                ),
                SummaryFigure(
                  label: 'Normales',
                  value: '${formatMinutes(summary.normalMinutes)} h',
                  kind: DataKind.normal,
                ),
                SummaryFigure(
                  label: 'Festivas',
                  value: '${formatMinutes(summary.festiveMinutes)} h',
                  kind: DataKind.festive,
                ),
              ],
            ),
            const SizedBox(height: Space.l),
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: Space.s,
              crossAxisSpacing: Space.s,
              childAspectRatio: 1,
              children: [
                for (final m in presetMinutes)
                  HourPresetButton(
                    minutes: m,
                    selected: selectedPreset(minutes) == m,
                    kind: dataKind,
                    arm: _armed != m
                        ? PresetArm.none
                        : _armedDelete
                        ? PresetArm.delete
                        : PresetArm.save,
                    onPressed: () => _presetTapped(
                      m,
                      isSelected: selectedPreset(minutes) == m,
                    ),
                  ),
                HourPresetButton(
                  minutes: minutes,
                  selected: isOtherSelected(minutes),
                  kind: dataKind,
                  text: isOtherSelected(minutes)
                      ? '${formatMinutes(minutes)} h'
                      : 'Otra',
                  semanticsLabel: 'Apuntar otra cantidad',
                  onPressed: _other,
                ),
              ],
            ),
            if (_armed != null)
              // La instrucción ocupa el hueco de «A cobrar» mientras dura la
              // marca, para que nada salte de sitio (013, RF-1, RF-3).
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: widget.money == null ? 0 : Sizes.undoReserve,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: Space.m),
                  child: _armHint(context),
                ),
              )
            else if (widget.money != null)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Sizes.undoReserve),
                child: Padding(
                  padding: const EdgeInsets.only(top: Space.m),
                  child: _monthMoney(context),
                ),
              ),
          ],
        ),
      ),
    );

    return SafeArea(
      bottom: false,
      // Los botones quedan fijos abajo; si la parte de arriba no cabe
      // (pantallas pequeñas o letra grande), se desplaza dentro del agua.
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _pointerDown,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerCancel,
        child: Column(
          children: [
            Expanded(
              child: Tide(
                value: minutes.toDouble(),
                max: _fullTideMinutes.toDouble(),
                kind: dataKind,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SingleChildScrollView(child: top),
                    SavedMark(trigger: _saves, kind: dataKind),
                  ],
                ),
              ),
            ),
            bottom,
          ],
        ),
      ),
    );
  }
}
