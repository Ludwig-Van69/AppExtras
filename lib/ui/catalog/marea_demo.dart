import 'dart:async';

import 'package:flutter/material.dart';

import '../components/app_nav_bar.dart';
import '../components/big_hours.dart';
import '../components/day_heading.dart';
import '../components/day_selector.dart';
import '../components/hour_preset_button.dart';
import '../components/info_button.dart';
import '../components/summary_figure.dart';
import '../components/tide.dart';
import '../components/undo.dart';
import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

const _weekdays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];
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
const _dayNames = ['Hoy', 'Ayer', 'Anteayer'];

// Horas en minutos enteros y euros en céntimos (constitución, principio 8).
const _normalPresets = [60, 90, 120, 150, 180, 210, 240, 300];
const _festivePresets = [240, 300, 360, 420, 480, 540, 600, 660];
const _rateCentsPerHour = {DataKind.normal: 1500, DataKind.festive: 2000};

/// Una jornada completa llena el agua, sea normal o festiva.
const _fullTideMinutes = 480;

/// Lo que ya se debía antes de estos tres días (dato inventado).
const _previousOwedCents = 41250;

int _cents(int minutes, DataKind kind) =>
    (minutes * _rateCentsPerHour[kind]! / 60).round();

/// Demostración de la pantalla de apuntar en estilo Marea (RF-25).
/// Usa datos inventados y no guarda nada.
class MareaDemo extends StatefulWidget {
  const MareaDemo({super.key, this.today});

  /// Fecha de «Hoy»; si es nula, la de hoy de verdad.
  final DateTime? today;

  @override
  State<MareaDemo> createState() => _MareaDemoState();
}

class _MareaDemoState extends State<MareaDemo> {
  int _day = 0;
  bool _towardsPast = true;
  final _minutes = [150, 60, 0];
  final _manualKind = <int, DataKind>{};
  UndoHandle? _undo;

  /// Doble toque, como en Apuntar (013, RF-1 a RF-4 y RF-20).
  int? _armed;
  Timer? _armTimer;

  @override
  void dispose() {
    // El aviso con «Deshacer» de esta pantalla no debe sobrevivirla.
    _undo?.dismiss();
    _armTimer?.cancel();
    super.dispose();
  }

  void _presetTapped(int m) {
    if (_armed == m) {
      _disarm();
      _minutes[_day] == m ? _delete() : _setMinutes(m);
      return;
    }
    _armTimer?.cancel();
    _armTimer = Timer(const Duration(seconds: 3), _disarm);
    setState(() => _armed = m);
  }

  void _disarm() {
    _armTimer?.cancel();
    if (_armed != null && mounted) setState(() => _armed = null);
  }

  DateTime _date(int i) {
    final t = widget.today ?? DateTime.now();
    return DateTime(t.year, t.month, t.day - i);
  }

  DataKind _kindOf(int i) =>
      _manualKind[i] ??
      (_date(i).weekday >= DateTime.saturday
          ? DataKind.festive
          : DataKind.normal);

  String _kindName(DataKind kind) =>
      kind == DataKind.festive ? 'Festiva' : 'Normal';

  void _goTo(int day) {
    if (day == _day) return;
    _armTimer?.cancel();
    _armed = null;
    setState(() {
      _towardsPast = day > _day;
      _day = day;
    });
  }

  /// Apuntar o cambiar el tipo se ve al momento y se corrige con otro toque,
  /// así que no lleva aviso (RF-20). Cualquier aviso de borrado anterior se
  /// quita, para que «Deshacer» no pise un cambio más reciente.
  void _apply(VoidCallback change) {
    _undo?.dismiss();
    _undo = null;
    setState(change);
  }

  void _setMinutes(int minutes) {
    final day = _day;
    if (_minutes[day] == minutes) return;
    _apply(() => _minutes[day] = minutes);
  }

  /// Borrar es lo único que no se arregla con otro toque: lleva aviso con
  /// «Deshacer», que vuelve al día afectado (RF-21, RF-22).
  void _delete() {
    final day = _day;
    final previous = _minutes[day];
    if (previous == 0) return;
    setState(() => _minutes[day] = 0);
    _undo = showUndo(
      context,
      message:
          '${formatMinutes(previous)} h borradas de ${_dayNames[day].toLowerCase()}',
      onUndo: () {
        _goTo(day);
        setState(() => _minutes[day] = previous);
      },
    );
  }

  void _toggleKind() {
    final day = _day;
    final next = _kindOf(day) == DataKind.festive
        ? DataKind.normal
        : DataKind.festive;
    _apply(() => _manualKind[day] = next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kind = _kindOf(_day);
    final presets = kind == DataKind.festive ? _festivePresets : _normalPresets;
    final date = _date(_day);
    var owed = _previousOwedCents;
    for (var i = 0; i < _minutes.length; i++) {
      owed += _cents(_minutes[i], _kindOf(i));
    }
    final water = c.of(kind).soft;

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
          Row(
            children: [
              Expanded(
                child: DaySelector(selected: _day, onChanged: _goTo),
              ),
              IconButton(
                tooltip: 'Volver al catálogo',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: Space.xxl),
          DayHeading(
            text:
                '${_weekdays[date.weekday - 1]}, ${date.day} de ${_months[date.month - 1]}',
            towardsPast: _towardsPast,
          ),
          // Sin papelera: se borra con doble toque en la cifra (012, RF-2).
          BigHours(minutes: _minutes[_day]),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.m,
            runSpacing: Space.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                hint: 'Toca para cambiar el tipo de hora',
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.of(kind).strong,
                    foregroundColor: c.of(kind).onStrong,
                  ),
                  onPressed: _toggleKind,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(
                    '${_kindName(kind)} · ${_rateCentsPerHour[kind]! ~/ 100} €/h',
                  ),
                ),
              ),
              Text(
                formatEuros(_cents(_minutes[_day], kind)),
                style: AppText.label,
              ),
            ],
          ),
          const SizedBox(height: Space.xl),
          const TextField(
            decoration: InputDecoration(
              labelText: 'Motivo, opcional',
              hintText: 'Por ejemplo, Taller Norte',
            ),
          ),
        ],
      ),
    );

    // Lo que se toca con el pulgar va abajo, sobre una hoja que flota en
    // el agua.
    final bottom = AnimatedContainer(
      duration: context.motion(Motion.theme),
      color: water,
      child: Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.sheet),
          ),
        ),
        // Abajo se reserva el hueco del aviso con «Deshacer», para que nunca
        // tape los botones de horas.
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.xl,
          Space.gutter,
          Sizes.undoReserve,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SummaryRow(
              children: [
                SummaryFigure(label: 'A cobrar', value: formatEuros(owed)),
                const SummaryFigure(
                  label: 'Bolsa',
                  value: '24 h',
                  kind: DataKind.bag,
                ),
                const SummaryFigure(
                  label: 'Vacaciones',
                  value: '8 días',
                  kind: DataKind.vacation,
                ),
              ],
            ),
            const SizedBox(height: Space.l),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: Space.s,
              crossAxisSpacing: Space.s,
              childAspectRatio: 1.4,
              children: [
                for (final m in presets)
                  HourPresetButton(
                    minutes: m,
                    selected: _minutes[_day] == m,
                    kind: kind,
                    arm: _armed != m
                        ? PresetArm.none
                        : _minutes[_day] == m
                        ? PresetArm.delete
                        : PresetArm.save,
                    onPressed: () => _presetTapped(m),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Datos inventados: nada se guarda.',
                    style: AppText.caption.copyWith(color: c.textSoft),
                  ),
                ),
                const InfoButton(
                  title: 'Demostración',
                  text:
                      'Esta pantalla sirve para revisar el estilo. Las horas, '
                      'los euros y los días son inventados y se pierden al salir.',
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      bottomNavigationBar: AppNavBar(
        current: AppSection.log,
        onChanged: (_) {},
      ),
      body: SafeArea(
        bottom: false,
        // Los botones quedan fijos abajo; si la parte de arriba no cabe
        // (pantallas pequeñas o letra grande), se desplaza dentro del agua.
        child: Column(
          children: [
            Expanded(
              child: Tide(
                value: _minutes[_day].toDouble(),
                max: _fullTideMinutes.toDouble(),
                kind: kind,
                child: SingleChildScrollView(child: top),
              ),
            ),
            bottom,
          ],
        ),
      ),
    );
  }
}
