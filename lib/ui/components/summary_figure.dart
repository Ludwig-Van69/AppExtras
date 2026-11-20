import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Resumen de una cifra con su etiqueta, p. ej. «A cobrar · 412,50 €».
class SummaryFigure extends StatelessWidget {
  const SummaryFigure({
    super.key,
    required this.label,
    required this.value,
    this.kind,
  });

  final String label;
  final String value;

  /// Si se indica, la cifra toma el color de ese tipo de dato.
  final DataKind? kind;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: c.textSoft),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.figure.copyWith(
                color: kind == null ? c.text : c.of(kind!).strong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de resúmenes con un hueco fijo entre ellos, para que las cifras no
/// se peguen ni con letra grande.
class SummaryRow extends StatelessWidget {
  const SummaryRow({super.key, required this.children});

  final List<SummaryFigure> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: Space.l),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}
