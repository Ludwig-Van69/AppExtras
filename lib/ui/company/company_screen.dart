import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/company.dart';
import '../components/info_button.dart';
import '../components/undo.dart';
import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'company_controller.dart';

/// Texto del ⓘ de la fecha de alta (026, interfaz).
const seniorityInfo =
    'Es la fecha de alta de tu vida laboral. Los días cuentan como la '
    'Seguridad Social: los días naturales desde el alta, con vacaciones, '
    'bajas y fines de semana';

/// «Hoy llevas 2.459 días» (RF-2).
String daysSoFar(Seniority s) =>
    'Hoy llevas ${formatCount(s.totalDays)} '
    '${s.totalDays == 1 ? 'día' : 'días'}';

/// Ajustes → Empresa (026, RF-1, RF-2, RF-6 a RF-8): nombre y fecha de alta,
/// opcionales. Cada cambio se guarda solo; borrar se puede deshacer.
class CompanyScreen extends StatefulWidget {
  const CompanyScreen({super.key, required this.company});

  final CompanyController company;

  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> {
  CompanyController get _c => widget.company;

  late final _name = TextEditingController(text: _c.company.name ?? '');
  UndoHandle? _undo;

  @override
  void dispose() {
    _undo?.dismiss();
    _name.dispose();
    super.dispose();
  }

  Future<void> _nameChanged(String text) async {
    setState(() {});
    await _c.save(_c.company.withName(text));
  }

  Future<void> _clearName() async {
    final old = _c.company.name;
    _name.clear();
    setState(() {});
    if (!await _c.save(_c.company.withName(null)) || !mounted) return;
    _undo = showUndo(
      context,
      message: 'Nombre borrado',
      onUndo: () {
        _name.text = old ?? '';
        setState(() {});
        _c.save(_c.company.withName(old));
      },
    );
  }

  Future<void> _pickStart() async {
    final today = _c.today;
    final current = _c.company.start;
    final d = await showDatePicker(
      context: context,
      helpText: 'Fecha de alta',
      initialDate: current == null || current.isAfter(today) ? today : current,
      firstDate: DateTime(Company.minYear),
      lastDate: today,
    );
    if (d == null) return;
    await _c.save(_c.company.withStart(d));
  }

  Future<void> _clearStart() async {
    final old = _c.company.start;
    if (!await _c.save(_c.company.withStart(null)) || !mounted) return;
    _undo = showUndo(
      context,
      message: 'Fecha de alta borrada',
      onUndo: () => _c.save(_c.company.withStart(old)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Empresa')),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final start = _c.company.start;
          final seniority = _c.seniority;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.s,
              Space.gutter,
              Space.xxxl,
            ),
            children: [
              Text(
                'Con la fecha de alta, Métricas te enseña tu antigüedad. '
                'Los cambios se guardan solos.',
                style: AppText.body.copyWith(color: c.textSoft),
              ),
              const SizedBox(height: Space.l),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(Company.maxName),
                ],
                onChanged: _nameChanged,
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Opcional',
                  suffixIcon: _name.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Borrar el nombre',
                          icon: const Icon(Icons.close),
                          onPressed: _clearName,
                        ),
                ),
              ),
              const SizedBox(height: Space.l),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.event_outlined, color: c.textSoft),
                title: Row(
                  children: [
                    Flexible(
                      child: Text('Fecha de alta', style: AppText.bodyStrong),
                    ),
                    const InfoButton(
                      title: 'Fecha de alta',
                      text: seniorityInfo,
                    ),
                  ],
                ),
                subtitle: Text(start == null ? 'Sin poner' : shortDate(start)),
                trailing: start == null
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        tooltip: 'Borrar la fecha de alta',
                        icon: const Icon(Icons.close),
                        onPressed: _clearStart,
                      ),
                onTap: _pickStart,
              ),
              if (seniority != null)
                Text(daysSoFar(seniority), style: AppText.body),
              if (_c.saveFailed)
                Padding(
                  padding: const EdgeInsets.only(top: Space.m),
                  child: Text(
                    'No se ha podido guardar el último cambio. Vuelve a '
                    'intentarlo.',
                    style: AppText.body.copyWith(color: c.error),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
