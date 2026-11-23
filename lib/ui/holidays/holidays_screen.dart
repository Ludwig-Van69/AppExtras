import 'package:flutter/material.dart';

import '../../domain/holidays.dart';
import '../components/info_button.dart';
import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'holidays_controller.dart';

/// Pantalla «Festivos» (Ajustes): interruptores y festivos propios (004).
class HolidaysScreen extends StatelessWidget {
  const HolidaysScreen({super.key, required this.holidays, this.clock});

  final HolidaysController holidays;

  /// Reloj para los tests; si es nulo, la hora real.
  final DateTime Function()? clock;

  DateTime get _now => (clock ?? DateTime.now)();

  String _when(Holiday h) {
    final year = _now.year;
    if (h.date != null) {
      return '${h.date!.day} de ${monthName(h.date!.month)} de ${h.date!.year}';
    }
    if (h.easterOffset != null) {
      final d = h.dateIn(year)!;
      return 'Cambia cada año · en $year: ${d.day} de ${monthName(d.month)}';
    }
    final base = '${h.day} de ${monthName(h.month!)}';
    return h.isCustom ? '$base · cada año' : base;
  }

  Future<void> _add(BuildContext context) async {
    final result = await showDialog<_NewHoliday>(
      context: context,
      builder: (_) => _AddDialog(today: _now),
    );
    if (result != null) {
      await holidays.addCustom(result.name, result.date, yearly: result.yearly);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Festivos')),
      body: ListenableBuilder(
        listenable: holidays,
        builder: (context, _) {
          final cal = holidays.calendar;
          Widget header(String text) => Padding(
            padding: const EdgeInsets.only(top: Space.l, bottom: Space.xs),
            child: Semantics(
              header: true,
              child: Text(text, style: AppText.title),
            ),
          );
          List<Holiday> group(HolidayGroup g) => [
            for (final h in cal.holidays)
              if (h.group == g) h,
          ];
          final mine = group(HolidayGroup.custom);
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.s,
              Space.gutter,
              Space.xxxl,
            ),
            children: [
              Text(
                'Los sábados y domingos siempre se proponen festivos. Estos '
                'festivos son un punto de partida: revísalos cada año con el '
                'calendario laboral oficial.',
                style: AppText.body.copyWith(color: c.textSoft),
              ),
              if (holidays.saveFailed)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: Text(
                    'No se han podido guardar los cambios; valen hasta que '
                    'cierres la app.',
                    style: AppText.body.copyWith(color: c.error),
                  ),
                ),
              header('Nacionales'),
              for (final h in group(HolidayGroup.national)) _tile(h, cal),
              Row(
                children: [
                  Expanded(child: header('Los míos')),
                  const Padding(
                    padding: EdgeInsets.only(top: Space.l),
                    child: InfoButton(
                      title: 'Festivos de tu zona',
                      text:
                          'Solo vienen los festivos nacionales. Añade aquí los '
                          'de tu comunidad autónoma y los dos locales de tu '
                          'municipio: los encontrarás en el calendario '
                          'laboral de tu comunidad y en la web de tu '
                          'ayuntamiento. Añade también los traslados (por '
                          'ejemplo, un festivo que cae en domingo y se pasa '
                          'al lunes). Los que cambian de fecha, como Jueves '
                          'Santo o una fiesta local, se añaden cada año como '
                          '«solo ese año».',
                    ),
                  ),
                ],
              ),
              if (mine.isEmpty)
                Text(
                  'Añade los de tu comunidad y tu municipio.',
                  style: AppText.body.copyWith(color: c.textSoft),
                ),
              for (final h in mine) _tile(h, cal),
              const SizedBox(height: Space.l),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir festivo'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(Holiday h, HolidayCalendar cal) {
    if (h.isCustom) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(h.name, style: AppText.bodyStrong),
        subtitle: Text(_when(h)),
        trailing: IconButton(
          tooltip: 'Borrar ${h.name}',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => holidays.removeCustom(h),
        ),
      );
    }
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(h.name, style: AppText.bodyStrong),
      subtitle: Text(_when(h)),
      value: cal.isEnabled(h),
      onChanged: (v) => holidays.setEnabled(h, v),
    );
  }
}

class _NewHoliday {
  const _NewHoliday(this.name, this.date, this.yearly);
  final String name;
  final DateTime date;
  final bool yearly;
}

class _AddDialog extends StatefulWidget {
  const _AddDialog({required this.today});
  final DateTime today;

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _name = TextEditingController();
  late DateTime _date = DateTime(
    widget.today.year,
    widget.today.month,
    widget.today.day,
  );
  bool _yearly = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Añadir festivo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              maxLength: maxHolidayNameLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.s),
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.event),
              label: Text(
                '${_date.day} de ${monthName(_date.month)} de ${_date.year}',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Se repite cada año'),
              value: _yearly,
              onChanged: (v) => setState(() => _yearly = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () =>
                    Navigator.of(context)
                        .pop(_NewHoliday(_name.text, _date, _yearly)),
          child: const Text('Añadir'),
        ),
      ],
    );
  }
}
