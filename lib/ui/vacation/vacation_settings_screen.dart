import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/vacations.dart';
import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'vacation_controller.dart';

/// Ajustes → Vacaciones (010, RF-1, RF-2): primer año, sus días, días al año
/// y correcciones de años concretos. Sin configurar se guarda con un botón;
/// después, cada cambio válido se guarda solo.
class VacationSettingsScreen extends StatefulWidget {
  const VacationSettingsScreen({super.key, required this.vacation});

  final VacationController vacation;

  @override
  State<VacationSettingsScreen> createState() => _VacationSettingsScreenState();
}

class _VacationSettingsScreenState extends State<VacationSettingsScreen> {
  VacationController get _v => widget.vacation;

  late int _firstYear = _v.settings?.firstYear ?? _v.today.year;
  late final _firstDays = TextEditingController(
    text: _v.settings == null ? '' : formatHalfDays(_v.settings!.firstHalfDays),
  );
  late final _yearlyDays = TextEditingController(
    text: formatHalfDays(_v.settings?.yearlyHalfDays ?? defaultYearlyHalfDays),
  );
  bool _tried = false;

  bool get _isNew => _v.settings == null;

  @override
  void dispose() {
    _firstDays.dispose();
    _yearlyDays.dispose();
    super.dispose();
  }

  static bool _valid(int? h) => h != null && h <= maxVacationHalfDays;

  String? get _problem {
    if (!_valid(parseHalfDays(_firstDays.text)) ||
        !_valid(parseHalfDays(_yearlyDays.text))) {
      return 'Escribe los días entre 0 y 60, enteros o con medio día (11,5).';
    }
    return null;
  }

  VacationSettings _build() => VacationSettings(
    firstYear: _firstYear,
    firstHalfDays: parseHalfDays(_firstDays.text)!,
    yearlyHalfDays: parseHalfDays(_yearlyDays.text)!,
    // Las correcciones de años anteriores al primero ya no cuentan.
    overrides: {
      for (final e in (_v.settings?.overrides ?? const <int, int>{}).entries)
        if (e.key >= _firstYear) e.key: e.value,
    },
  );

  Future<void> _changed() async {
    setState(() {});
    if (_isNew || _problem != null) return;
    final s = _build();
    if (s != _v.settings) await _v.saveSettings(s);
  }

  Future<void> _create() async {
    setState(() => _tried = true);
    if (_problem != null) return;
    await _v.saveSettings(_build());
    if (mounted) setState(() {});
  }

  Future<void> _editYear(int year) async {
    final s = _v.settings!;
    final current = s.generatedHalfDays(year, _v.today.year);
    final result = await showDialog<int?>(
      context: context,
      builder: (context) => _YearDialog(
        year: year,
        initial: formatHalfDays(current),
        corrected: s.overrides.containsKey(year),
      ),
    );
    if (result == null || !mounted) return;
    final overrides = {...s.overrides};
    if (result < 0) {
      overrides.remove(year); // quitar la corrección
    } else {
      overrides[year] = result;
    }
    await _v.saveSettings(s.copyWith(overrides: overrides));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final problem = _problem;
    final showProblem = problem != null && (_tried || !_isNew);
    final thisYear = _v.today.year;
    final s = _v.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Vacaciones')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.s,
          Space.gutter,
          Space.xxxl,
        ),
        children: [
          Text(
            'Los días se generan de golpe el 1 de enero. Escríbelos en días '
            'laborables; puedes usar medio día (11,5).',
            style: AppText.body.copyWith(color: c.textSoft),
          ),
          const SizedBox(height: Space.l),
          DropdownButtonFormField<int>(
            initialValue: _firstYear,
            decoration: const InputDecoration(labelText: 'Primer año'),
            items: [
              for (var y = firstVacationYear; y <= thisYear; y++)
                DropdownMenuItem(value: y, child: Text('$y')),
            ],
            onChanged: (y) {
              if (y == null) return;
              _firstYear = y;
              _changed();
            },
          ),
          const SizedBox(height: Space.l),
          TextField(
            controller: _firstDays,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              LengthLimitingTextInputFormatter(4),
            ],
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(
              labelText: 'Días del primer año',
              hintText: 'Por ejemplo, 11,5 si entraste a mitad de año',
              suffixText: 'días',
            ),
          ),
          const SizedBox(height: Space.l),
          TextField(
            controller: _yearlyDays,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              LengthLimitingTextInputFormatter(4),
            ],
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(
              labelText: 'Días al año',
              suffixText: 'días',
            ),
          ),
          if (showProblem)
            Padding(
              padding: const EdgeInsets.only(top: Space.m),
              child: Text(
                _isNew ? problem : '$problem Hasta entonces no se guarda.',
                style: AppText.body.copyWith(color: c.error),
              ),
            ),
          ListenableBuilder(
            listenable: _v,
            builder: (context, _) => _v.saveFailed
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
          if (_isNew) ...[
            const SizedBox(height: Space.xl),
            FilledButton(onPressed: _create, child: const Text('Guardar')),
          ] else ...[
            const SizedBox(height: Space.l),
            Text(
              'Los cambios se guardan solos.',
              style: AppText.body.copyWith(color: c.textSoft),
            ),
            const SizedBox(height: Space.xl),
            Text(
              'Días de cada año',
              style: AppText.label.copyWith(color: c.textSoft),
            ),
            Text(
              'Toca un año para corregirlo si ese año fue distinto.',
              style: AppText.body.copyWith(color: c.textSoft),
            ),
            for (var y = s!.firstYear; y <= thisYear; y++)
              ListTile(
                key: ValueKey('anio-$y'),
                contentPadding: EdgeInsets.zero,
                title: Text('$y', style: AppText.bodyStrong),
                subtitle: s.overrides.containsKey(y)
                    ? const Text('Corregido a mano')
                    : null,
                trailing: Text(
                  '${formatHalfDays(s.generatedHalfDays(y, thisYear))} días',
                  style: AppText.bodyStrong,
                ),
                onTap: () => _editYear(y),
              ),
          ],
        ],
      ),
    );
  }
}

/// Corregir los días de un año. Devuelve los medios días nuevos, −1 para
/// quitar la corrección o nulo si se cancela.
class _YearDialog extends StatefulWidget {
  const _YearDialog({
    required this.year,
    required this.initial,
    required this.corrected,
  });

  final int year;
  final String initial;
  final bool corrected;

  @override
  State<_YearDialog> createState() => _YearDialogState();
}

class _YearDialogState extends State<_YearDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = parseHalfDays(_controller.text);
    final valid = value != null && value <= maxVacationHalfDays;
    return AlertDialog(
      title: Text('Días de ${widget.year}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          LengthLimitingTextInputFormatter(4),
        ],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          suffixText: 'días',
          errorText: valid ? null : 'Entre 0 y 60, enteros o con medio día.',
        ),
      ),
      actions: [
        if (widget.corrected)
          TextButton(
            onPressed: () => Navigator.of(context).pop(-1),
            child: const Text('Quitar corrección'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: valid ? () => Navigator.of(context).pop(value) : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
