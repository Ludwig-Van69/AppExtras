import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Estados vacío, cargando y error, cada uno con un texto que dice qué hacer
/// (RF-19).
class StateMessage extends StatelessWidget {
  const StateMessage.empty({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  }) : _kind = _StateKind.empty;

  const StateMessage.loading({super.key, required this.message})
    : title = null,
      actionLabel = null,
      onAction = null,
      _kind = _StateKind.loading;

  const StateMessage.error({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  }) : _kind = _StateKind.error;

  final String? title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final _StateKind _kind;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = switch (_kind) {
      _StateKind.empty => Icon(
        Icons.water_drop_outlined,
        size: Sizes.stateIcon,
        color: c.normal.strong,
      ),
      _StateKind.loading => const SizedBox.square(
        dimension: 32,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
      _StateKind.error => Icon(
        Icons.error_outline,
        size: Sizes.stateIcon,
        color: c.error,
      ),
    };

    final body = Semantics(
      liveRegion: _kind != _StateKind.empty,
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: Space.m),
            if (title != null) ...[
              Text(title!, textAlign: TextAlign.center, style: AppText.title),
              const SizedBox(height: Space.xs),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: c.textSoft),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Space.l),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
    return _kind == _StateKind.loading ? _ShowIfSlow(child: body) : body;
  }
}

/// Lo que tarda menos que esto no enseña «cargando»: así, al abrir la app,
/// no parpadea un texto de un instante entre el arranque y la pantalla.
const loadingDelay = Duration(milliseconds: 600);

class _ShowIfSlow extends StatefulWidget {
  const _ShowIfSlow({required this.child});
  final Widget child;

  @override
  State<_ShowIfSlow> createState() => _ShowIfSlowState();
}

class _ShowIfSlowState extends State<_ShowIfSlow> {
  late final Timer _timer;
  var _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(loadingDelay, () => setState(() => _visible = true));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _visible ? 1 : 0,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200),
    child: _visible ? widget.child : const SizedBox.shrink(),
  );
}

enum _StateKind { empty, loading, error }
