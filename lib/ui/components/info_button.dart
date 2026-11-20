import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Botón ⓘ que abre una explicación breve desde abajo.
class InfoButton extends StatelessWidget {
  const InfoButton({super.key, required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Más información: $title',
      icon: Icon(Icons.info_outline, color: context.colors.textSoft),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          // Con letra grande o un texto largo, se desplaza en vez de cortarse.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.xxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.title),
                const SizedBox(height: Space.s),
                Text(text, style: AppText.body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
