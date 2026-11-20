import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/day_entry.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Campo del motivo con sugerencias (RF-14 a RF-17).
///
/// Lo escrito se guarda al cabo de 1 s sin escribir, al salir del campo, al
/// cambiar de día y cuando la app pasa a segundo plano, siempre en el día en
/// que se escribió.
class ReasonField extends StatefulWidget {
  const ReasonField({
    super.key,
    required this.date,
    required this.reason,
    required this.enabled,
    required this.suggestionsFor,
    required this.onSave,
  });

  final DateTime date;

  /// El motivo guardado de [date].
  final String? reason;

  /// Falso mientras el día no tiene horas (RF-15).
  final bool enabled;
  final List<String> Function(String query) suggestionsFor;
  final void Function(DateTime date, String text) onSave;

  static const saveDelay = Duration(seconds: 1);

  /// Cuánto se ve «Guardado» tras guardar (006, RF-5).
  static const savedNoticeTime = Duration(seconds: 2);

  @override
  State<ReasonField> createState() => _ReasonFieldState();
}

class _ReasonFieldState extends State<ReasonField> with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  Timer? _noticeTimer;
  bool _dirty = false;

  /// «Guardado» visible durante [ReasonField.savedNoticeTime].
  bool _justSaved = false;

  /// El ✓ solo se ve si lo que hay en el campo es lo guardado: si el guardado
  /// falla, el motivo vuelve al anterior y el ✓ desaparece.
  bool get _isSaved =>
      widget.enabled &&
      !_dirty &&
      widget.reason != null &&
      normalizeReason(_text.text) == widget.reason;

  @override
  void initState() {
    super.initState();
    _text.text = widget.reason ?? '';
    _focus.addListener(() {
      if (!_focus.hasFocus) _flush(widget.date);
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(ReasonField old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) {
      // Lo escrito va al día en que se escribió.
      _flush(old.date, afterFrame: true);
      _setText(widget.reason);
    } else if (!_dirty && !_focus.hasFocus && widget.reason != old.reason) {
      _setText(widget.reason); // p. ej. tras Deshacer
    } else if (!widget.enabled && old.enabled) {
      _timer?.cancel();
      _dirty = false;
      _setText(null); // el día se ha borrado
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flush(widget.date);
  }

  @override
  void dispose() {
    _flush(widget.date, afterFrame: true);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _noticeTimer?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setText(String? value) {
    final v = value ?? '';
    if (_text.text != v) _text.text = v;
  }

  void _changed(String _) {
    _dirty = true;
    _noticeTimer?.cancel();
    setState(() => _justSaved = false);
    _timer?.cancel();
    final date = widget.date;
    _timer = Timer(ReasonField.saveDelay, () => _flush(date));
  }

  /// Guarda lo escrito en [date]. Mientras se construye la pantalla (al
  /// cambiar de día o al cerrarla) se espera al final del fotograma, porque
  /// guardar redibuja la pantalla.
  void _flush(DateTime date, {bool afterFrame = false}) {
    _timer?.cancel();
    _timer = null;
    if (!_dirty) return;
    _dirty = false;
    final text = _text.text;
    final save = widget.onSave;
    if (afterFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => save(date, text));
    } else {
      save(date, text);
      _showSaved();
    }
  }

  void _showSaved() {
    if (!mounted) return;
    _noticeTimer?.cancel();
    setState(() => _justSaved = true);
    _noticeTimer = Timer(ReasonField.savedNoticeTime, () {
      if (mounted) setState(() => _justSaved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RawAutocomplete<String>(
      textEditingController: _text,
      focusNode: _focus,
      optionsBuilder: (value) =>
          widget.enabled ? widget.suggestionsFor(value.text) : const [],
      onSelected: (choice) {
        _dirty = true;
        _flush(widget.date);
        _focus.unfocus();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: widget.enabled,
        onChanged: _changed,
        onSubmitted: (_) => onSubmit(),
        textCapitalization: TextCapitalization.sentences,
        inputFormatters: [LengthLimitingTextInputFormatter(maxReasonLength)],
        decoration: InputDecoration(
          labelText: 'Motivo, opcional',
          hintText: widget.enabled
              ? 'Por ejemplo, Taller Norte'
              : 'Apunta primero las horas',
          floatingLabelBehavior: widget.enabled
              ? FloatingLabelBehavior.auto
              : FloatingLabelBehavior.always,
          suffixIcon: _isSaved
              ? Row(
                  key: const ValueKey('motivo-guardado'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_justSaved)
                      Text(
                        'Guardado',
                        style: AppText.label.copyWith(color: c.normal.strong),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s),
                      child: Icon(
                        Icons.check_circle,
                        color: c.normal.strong,
                        semanticLabel: 'Motivo guardado',
                      ),
                    ),
                  ],
                )
              : null,
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final o in options)
                  ListTile(
                    title: Text(
                      o,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelected(o),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
