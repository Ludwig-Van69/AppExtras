import 'package:flutter/material.dart';

import '../../domain/hour_options.dart';
import '../components/haptics.dart';
import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Si el día no tiene horas, la rueda empieza justo después del último
/// botón (RF-8).
const _startMinutes = 330;

/// Alto de cada cifra de la rueda.
const _itemExtent = 52.0;

/// Ventana «Otra»: una rueda de 0,5 a 24 h en medias horas (RF-8).
/// Devuelve los minutos elegidos, 0 si se pide borrar el día (012, RF-3)
/// o nulo si se cancela.
Future<int?> showOtherHoursDialog(
  BuildContext context, {
  required int currentMinutes,
  required DataKind kind,
}) => showDialog<int>(
  context: context,
  builder: (_) => _OtherHoursDialog(current: currentMinutes, kind: kind),
);

class _OtherHoursDialog extends StatefulWidget {
  const _OtherHoursDialog({required this.current, required this.kind});

  final int current;
  final DataKind kind;

  @override
  State<_OtherHoursDialog> createState() => _OtherHoursDialogState();
}

class _OtherHoursDialogState extends State<_OtherHoursDialog> {
  late int _index = otherMinutes.indexOf(
    isValidChoice(widget.current) ? widget.current : _startMinutes,
  );
  late final _wheel = FixedExtentScrollController(initialItem: _index);

  int get _minutes => otherMinutes[_index];

  @override
  void dispose() {
    _wheel.dispose();
    super.dispose();
  }

  void _moveTo(int index) {
    if (index < 0 || index >= otherMinutes.length) return;
    _wheel.animateToItem(
      index,
      duration: context.motion(Motion.medium),
      curve: Curves.easeOutCubic,
    );
    // Sin animaciones, la rueda salta al momento; se fija igualmente.
    if (context.motion(Motion.medium) == Duration.zero) {
      _wheel.jumpToItem(index);
    }
  }

  String _phrase(int i) =>
      i < 0 || i >= otherMinutes.length ? '' : hoursPhrase(otherMinutes[i]);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = c.of(widget.kind);
    final scaler = MediaQuery.textScalerOf(context);
    final extent = scaler.scale(_itemExtent);

    return AlertDialog(
      title: const Text('¿Cuántas horas?'),
      content: SizedBox(
        height: extent * 5,
        width: double.maxFinite,
        child: Semantics(
          label: 'Horas',
          value: _phrase(_index),
          // En los extremos no hay «subir» o «bajar».
          increasedValue: _phrase(_index + 1),
          decreasedValue: _phrase(_index - 1),
          onIncrease: _index < otherMinutes.length - 1
              ? () => _moveTo(_index + 1)
              : null,
          onDecrease: _index > 0 ? () => _moveTo(_index - 1) : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Franja que marca la cifra elegida.
              Container(
                height: extent,
                decoration: BoxDecoration(
                  color: k.soft,
                  borderRadius: BorderRadius.circular(Radii.medium),
                ),
              ),
              ExcludeSemantics(
                child: ListWheelScrollView.useDelegate(
                  controller: _wheel,
                  itemExtent: extent,
                  physics: const FixedExtentScrollPhysics(),
                  diameterRatio: 1.8,
                  perspective: 0.004,
                  onSelectedItemChanged: (i) {
                    Haptics.select();
                    setState(() => _index = i);
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: otherMinutes.length,
                    builder: (context, i) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _moveTo(i),
                      child: Center(
                        child: Text(
                          '${formatMinutes(otherMinutes[i])} h',
                          style: i == _index
                              ? AppText.display.copyWith(color: c.text)
                              : AppText.title.copyWith(color: c.textSoft),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        // Devuelve 0: borrar las horas del día (012, RF-3).
        if (widget.current > 0)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: c.error),
            onPressed: () => Navigator.of(context).pop(0),
            child: const Text('Borrar'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: k.strong,
            foregroundColor: k.onStrong,
          ),
          onPressed: () => Navigator.of(context).pop(_minutes),
          child: const Text('Apuntar'),
        ),
      ],
    );
  }
}
