import 'package:flutter/material.dart';

import '../components/app_nav_bar.dart';
import '../components/big_hours.dart';
import '../components/confirm_dialog.dart';
import '../components/day_selector.dart';
import '../components/hour_preset_button.dart';
import '../components/info_button.dart';
import '../components/mosaic.dart';
import '../components/state_message.dart';
import '../components/summary_figure.dart';
import '../components/tide.dart';
import '../components/undo.dart';
import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../help_screen.dart';
import 'marea_demo.dart';

/// Catálogo del sistema visual: todas las piezas juntas, con datos
/// inventados, para revisarlas en los dos temas (RF-24).
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  int _day = 0;
  int _tideMinutes = 150;
  DataKind _tileKind = DataKind.normal;
  AppSection _section = AppSection.log;
  int _minutes = 150;
  UndoHandle? _undo;

  @override
  void dispose() {
    _undo?.dismiss();
    super.dispose();
  }

  // Mismo sistema de edición que la app: apuntar sin aviso; borrar, con
  // aviso y «Deshacer».
  void _setMinutes(int minutes) {
    if (_minutes == minutes) return;
    _undo?.dismiss();
    _undo = null;
    setState(() => _minutes = minutes);
  }

  void _delete() {
    final previous = _minutes;
    if (previous == 0) return;
    setState(() => _minutes = 0);
    _undo = showUndo(
      context,
      message: '${formatMinutes(previous)} h borradas de hoy',
      onUndo: () => setState(() => _minutes = previous),
    );
  }

  // Días inventados, del lunes 5 de octubre al miércoles 4 de noviembre de 2026.
  List<MosaicDay> get _mosaic {
    const pattern = {
      1: DataKind.normal,
      2: DataKind.normal,
      4: DataKind.normal,
      5: DataKind.festive,
      7: DataKind.normal,
      8: DataKind.normal,
      9: DataKind.normal,
      14: DataKind.vacation,
      15: DataKind.vacation,
      16: DataKind.vacation,
      17: DataKind.vacation,
      18: DataKind.vacation,
      22: DataKind.normal,
      23: DataKind.normal,
      25: DataKind.normal,
      26: DataKind.festive,
      28: DataKind.normal,
    };
    return [
      for (var i = 0; i < 31; i++)
        MosaicDay(DateTime(2026, 10, 5 + i), i == 29 ? _tileKind : pattern[i]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = ThemeScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sistema visual'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Ayuda',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen())),
          ),
        ],
      ),
      bottomNavigationBar: AppNavBar(
        current: _section,
        onChanged: (s) => setState(() => _section = s),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.s,
          Space.gutter,
          Space.xxxl,
        ),
        children: [
          _Section(
            title: 'Tema',
            child: ValueListenableBuilder<ThemeChoice>(
              valueListenable: theme,
              builder: (context, choice, _) => SegmentedButton<ThemeChoice>(
                showSelectedIcon: false,
                segments: [
                  for (final t in ThemeChoice.values)
                    ButtonSegment(
                      value: t,
                      // Siempre en una línea: si no cabe, se encoge un poco.
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(t.label, maxLines: 1, softWrap: false),
                      ),
                    ),
                ],
                selected: {choice},
                onSelectionChanged: (s) => theme.value = s.first,
              ),
            ),
          ),
          _Section(
            title: 'Demostración',
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const MareaDemo()),
              ),
              icon: const Icon(Icons.water),
              label: const Text('Abrir la pantalla de apuntar'),
            ),
          ),
          _Section(
            title: 'Colores por tipo',
            child: Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final k in DataKind.values)
                  Chip(
                    avatar: CircleAvatar(backgroundColor: c.of(k).strong),
                    label: Text(kindLabel(k)),
                    labelStyle: AppText.label.copyWith(color: c.text),
                    backgroundColor: c.of(k).soft,
                    side: BorderSide.none,
                  ),
              ],
            ),
          ),
          _Section(
            title: 'Tipografía',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('412,50 €', style: AppText.display),
                Text('Título de sección', style: AppText.title),
                Text(
                  'Texto normal para explicar algo con calma.',
                  style: AppText.body,
                ),
                Text(
                  'Etiqueta',
                  style: AppText.label.copyWith(color: c.textSoft),
                ),
              ],
            ),
          ),
          _Section(
            title: 'Marea',
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.medium),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.background,
                      border: Border.all(color: c.line),
                      borderRadius: BorderRadius.circular(Radii.medium),
                    ),
                    child: Tide(
                      value: _tideMinutes.toDouble(),
                      max: 480,
                      kind: DataKind.normal,
                      height: 160,
                    ),
                  ),
                ),
                Slider(
                  value: _tideMinutes.toDouble(),
                  max: 480,
                  divisions: 16,
                  label: '${formatMinutes(_tideMinutes)} h',
                  semanticFormatterCallback: (v) => hoursPhrase(v.round()),
                  onChanged: (v) => setState(() => _tideMinutes = v.round()),
                ),
              ],
            ),
          ),
          _Section(
            title: 'Mosaico',
            trailing: const InfoButton(
              title: 'Mosaico',
              text:
                  'Cada baldosa es un día. Su color dice si hubo horas '
                  'normales, festivas o vacaciones. Los días que aún no han '
                  'llegado solo tienen el contorno.',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Mosaic(
                  days: _mosaic,
                  selected: DateTime(2026, 11, 3),
                  today: DateTime(2026, 11, 3),
                  animateEntrance: true,
                ),
                const SizedBox(height: Space.s),
                OutlinedButton(
                  onPressed: () => setState(
                    () => _tileKind = _tileKind == DataKind.normal
                        ? DataKind.festive
                        : DataKind.normal,
                  ),
                  child: const Text('Cambiar el tipo del 3 nov'),
                ),
              ],
            ),
          ),
          _Section(
            title: 'Apuntar',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DaySelector(
                  selected: _day,
                  onChanged: (i) => setState(() => _day = i),
                ),
                const SizedBox(height: Space.l),
                BigHours(minutes: _minutes, onDelete: _delete),
                const SizedBox(height: Space.l),
                Row(
                  children: [
                    for (final m in const [120, 150, 180]) ...[
                      Expanded(
                        child: HourPresetButton(
                          minutes: m,
                          selected: _minutes == m,
                          kind: DataKind.normal,
                          onPressed: () => _setMinutes(m),
                        ),
                      ),
                      if (m != 180) const SizedBox(width: Space.s),
                    ],
                  ],
                ),
                const SizedBox(height: Space.l),
                const SummaryRow(
                  children: [
                    SummaryFigure(label: 'A cobrar', value: '412,50 €'),
                    SummaryFigure(
                      label: 'Bolsa',
                      value: '24 h',
                      kind: DataKind.bag,
                    ),
                    SummaryFigure(
                      label: 'Vacaciones',
                      value: '8 días',
                      kind: DataKind.vacation,
                    ),
                  ],
                ),
              ],
            ),
          ),
          _Section(
            title: 'Botones y campos',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () {},
                  child: const Text('Guardar copia'),
                ),
                const SizedBox(height: Space.s),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Elegir carpeta'),
                ),
                const SizedBox(height: Space.m),
                const TextField(
                  decoration: InputDecoration(labelText: 'Motivo, opcional'),
                ),
                const SizedBox(height: Space.m),
                DropdownMenu<String>(
                  expandedInsets: EdgeInsets.zero,
                  label: const Text('Tipo de hora'),
                  initialSelection: 'normal',
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(value: 'normal', label: 'Normal'),
                    DropdownMenuEntry(value: 'festiva', label: 'Festiva'),
                  ],
                ),
              ],
            ),
          ),
          const _Section(
            title: 'Tarjetas y listas',
            child: Card(
              child: Column(
                children: [
                  ListTile(
                    title: Text('Octubre'),
                    subtitle: Text('Papel entregado'),
                    trailing: Text('270,00 €'),
                  ),
                  Divider(),
                  ListTile(
                    title: Text('Septiembre'),
                    subtitle: Text('Cobrado'),
                    trailing: Text('270,00 €'),
                  ),
                ],
              ),
            ),
          ),
          _Section(
            title: 'Diálogos y avisos',
            child: Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                OutlinedButton(
                  onPressed: () => confirmDelete(
                    context,
                    title: '¿Borrar esta copia?',
                    message:
                        'Se borrará la copia del 3 de noviembre. '
                        'No se puede deshacer.',
                  ),
                  child: const Text('Ver confirmación'),
                ),
                OutlinedButton(
                  onPressed: () => _undo = showUndo(
                    context,
                    message: '2,5 h borradas de hoy',
                    onUndo: () {},
                  ),
                  child: const Text('Ver aviso'),
                ),
              ],
            ),
          ),
          _Section(
            title: 'Estados',
            child: Card(
              child: Column(
                children: [
                  const StateMessage.empty(
                    title: 'Aún no hay horas',
                    message: 'Toca unas horas abajo para apuntar las de hoy.',
                  ),
                  const Divider(),
                  const StateMessage.loading(message: 'Cargando tus horas…'),
                  const Divider(),
                  StateMessage.error(
                    title: 'No se ha podido leer la copia',
                    message: 'Elige otra carpeta o vuelve a intentarlo.',
                    actionLabel: 'Reintentar',
                    onAction: () {},
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: AppText.title),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: Space.m),
          child,
        ],
      ),
    );
  }
}
