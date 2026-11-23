import 'package:flutter/material.dart';

import '../../domain/month_theme.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'month_decor.dart';

/// Un día del Mosaico. [kind] es nulo si el día no tiene datos.
@immutable
class MosaicDay {
  const MosaicDay(this.date, [this.kind, this.caption, this.captionLabel])
    : muted = false,
      half = false;

  /// Medio día de vacaciones: la baldosa va pintada a medias (012, RF-11).
  const MosaicDay.half(this.date, this.kind, [this.caption, this.captionLabel])
    : muted = false,
      half = true;

  /// Sábado, domingo o festivo sin datos: sin relleno y con el contorno en
  /// coral (011, RF-3; 013, RF-6).
  const MosaicDay.muted(this.date)
    : kind = null,
      caption = null,
      captionLabel = null,
      muted = true,
      half = false;

  final bool muted;

  /// Pintada a medias, en diagonal: medio día (012, RF-11).
  final bool half;

  final DateTime date;
  final DataKind? kind;

  /// Cifra pequeña bajo el número, p. ej. las horas del día: «2,5».
  final String? caption;

  /// Cómo lee el lector de pantalla [caption], p. ej. «2,5 horas».
  final String? captionLabel;
}

/// Nombre de cada tipo, para la leyenda y los lectores de pantalla (RF-5).
String kindLabel(DataKind kind) => switch (kind) {
  DataKind.normal => 'Normal',
  DataKind.festive => 'Festiva',
  DataKind.vacation => 'Vacaciones',
  DataKind.bag => 'Bolsa',
};

const _weekdays = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// Mosaico: los días en una cuadrícula de lunes a domingo (RF-12).
class Mosaic extends StatefulWidget {
  const Mosaic({
    super.key,
    required this.days,
    this.selected,
    this.today,
    this.showLegend = true,
    this.animateEntrance = false,
    this.onTap,
    this.onLongPress,
    this.tileHeight = Sizes.tile,
    this.markOf,
    this.minWeeks = 0,
  });

  /// Filas mínimas: las que falten se dejan en blanco para que el alto no
  /// cambie de un mes a otro (un mes ocupa de 4 a 6 semanas).
  final int minWeeks;

  /// Detalle de temporada de cada día, o nulo (013, RF-9).
  final DayMark? Function(DateTime date)? markOf;

  /// Lo que tarda en aparecer el Mosaico entero en ola (RF-32).
  static const entranceDuration = Motion.mosaicEntrance;

  /// Días seguidos, del más antiguo al más reciente.
  final List<MosaicDay> days;
  final DateTime? selected;

  /// Los días posteriores se dibujan como futuros (solo el contorno).
  final DateTime? today;
  final bool showLegend;

  /// Si las baldosas aparecen en ola diagonal al mostrarse.
  final bool animateEntrance;

  /// Si no es nulo, cada día (salvo los futuros) se puede tocar. El hueco
  /// entre baldosas también cuenta, para que el dedo acierte mejor.
  final ValueChanged<DateTime>? onTap;

  /// Pulsación larga sobre un día (solo si [onTap] no es nulo).
  final ValueChanged<DateTime>? onLongPress;
  final double tileHeight;

  /// Reparte los días en semanas de 7 huecos; los huecos sin día son nulos.
  static List<List<MosaicDay?>> weeksOf(List<MosaicDay> days) {
    if (days.isEmpty) return const [];
    final cells = <MosaicDay?>[
      ...List<MosaicDay?>.filled(days.first.date.weekday - 1, null),
      ...days,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return [for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7)];
  }

  @override
  State<Mosaic> createState() => _MosaicState();
}

class _MosaicState extends State<Mosaic> with SingleTickerProviderStateMixin {
  late final _entrance = AnimationController(
    vsync: this,
    duration: Mosaic.entranceDuration,
    value: widget.animateEntrance ? 0 : 1,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.motion(Motion.medium) == Duration.zero) {
      _entrance.value = 1;
    } else if (widget.animateEntrance) {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final weeks = [...Mosaic.weeksOf(widget.days)];
    while (weeks.length < widget.minWeeks) {
      weeks.add(List<MosaicDay?>.filled(7, null));
    }
    final diagonals = weeks.length + 6;
    final tappable = widget.onTap != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              for (final d in _weekdays)
                Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: AppText.caption.copyWith(color: c.textSoft),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.s),
        for (final (row, week) in weeks.indexed)
          Padding(
            padding: EdgeInsets.only(bottom: tappable ? 0 : Space.tileGap),
            child: Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0 && !tappable) const SizedBox(width: Space.tileGap),
                  Expanded(
                    child: week[i] == null
                        ? SizedBox(
                            height:
                                widget.tileHeight +
                                (tappable ? Space.tileGap : 0),
                          )
                        : _cell(
                            week[i]!,
                            entranceStart: (row + i) / diagonals * 0.65,
                          ),
                  ),
                ],
              ],
            ),
          ),
        if (widget.showLegend) ...[
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.l,
            runSpacing: Space.s,
            children: [
              for (final kind in const [
                DataKind.normal,
                DataKind.festive,
                DataKind.vacation,
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: Sizes.legendSwatch,
                      height: Sizes.legendSwatch,
                      decoration: BoxDecoration(
                        color: c.of(kind).fill,
                        borderRadius: BorderRadius.circular(Radii.tiny),
                      ),
                    ),
                    const SizedBox(width: Space.tileGap),
                    Text(kindLabel(kind), style: AppText.caption),
                  ],
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: Sizes.legendSwatch,
                    height: Sizes.legendSwatch,
                    decoration: BoxDecoration(
                      border: Border.all(color: c.festive.strong, width: 1.5),
                      borderRadius: BorderRadius.circular(Radii.tiny),
                    ),
                  ),
                  const SizedBox(width: Space.tileGap),
                  Text('Festivo', style: AppText.caption),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

extension on _MosaicState {
  Widget _cell(MosaicDay day, {required double entranceStart}) {
    final today = widget.today;
    final future =
        today != null &&
        day.date.isAfter(DateTime(today.year, today.month, today.day));
    final tile = _Tile(
      entrance: _entrance,
      entranceStart: entranceStart,
      day: day,
      height: widget.tileHeight,
      future: future,
      mark: widget.markOf?.call(day.date),
      tappable: widget.onTap != null && !future,
      selected:
          widget.selected != null &&
          DateUtils.isSameDay(widget.selected, day.date),
    );
    final onTap = widget.onTap;
    if (onTap == null) return tile;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: future ? null : () => onTap(day.date),
      onLongPress: future || widget.onLongPress == null
          ? null
          : () => widget.onLongPress!(day.date),
      child: Padding(
        padding: const EdgeInsets.all(Space.tileGap / 2),
        child: tile,
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({
    required this.day,
    required this.selected,
    required this.future,
    required this.height,
    required this.tappable,
    required this.entrance,
    required this.entranceStart,
    this.mark,
  });

  final MosaicDay day;
  final DayMark? mark;
  final bool selected;
  final bool future;
  final double height;
  final bool tappable;
  final AnimationController entrance;

  /// Momento (de 0 a 1) en que empieza a aparecer esta baldosa.
  final double entranceStart;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> with SingleTickerProviderStateMixin {
  late final _jump = AnimationController(vsync: this, duration: Motion.medium);
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.16), weight: 40),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.16,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 60,
    ),
  ]).animate(_jump);

  // La entrada se crea una sola vez por baldosa y se libera al cerrarla.
  late CurvedAnimation _appear = _curve();

  CurvedAnimation _curve() => CurvedAnimation(
    parent: widget.entrance,
    curve: Interval(
      widget.entranceStart,
      widget.entranceStart + 0.35,
      curve: Curves.easeOutBack,
    ),
  );

  @override
  void didUpdateWidget(_Tile old) {
    super.didUpdateWidget(old);
    if (old.entrance != widget.entrance ||
        old.entranceStart != widget.entranceStart) {
      _appear.dispose();
      _appear = _curve();
    }
    // Un pequeño salto cuando la baldosa cambia de tipo (RF-13).
    if (old.day.kind != widget.day.kind &&
        context.motion(Motion.medium) > Duration.zero) {
      _jump.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _appear.dispose();
    _jump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kind = widget.future ? null : widget.day.kind;
    final date = widget.day.date;
    final muted = widget.day.muted && kind == null;
    final festiveLine = c.festive.strong;
    final bg = widget.future || muted
        ? Colors.transparent
        : kind == null
        ? c.empty
        : c.of(kind).fill;
    final half = kind != null && widget.day.half;
    // A medias, el texto cae sobre los dos colores: va en el del texto.
    final fg = kind == null
        ? (muted && !widget.future ? festiveLine : c.textSoft)
        : half
        ? c.text
        : c.of(kind).onFill;
    final caption = widget.future ? null : widget.day.caption;
    final captionLabel = widget.day.captionLabel ?? caption;
    final label =
        '${date.day} ${_months[date.month - 1]}: '
        '${widget.future
            ? 'aún no ha llegado'
            : muted
            ? 'no laborable'
            : kind == null
            ? 'sin datos'
            : kindLabel(kind)}'
        '${half ? ', medio día' : ''}'
        '${captionLabel == null ? '' : ', $captionLabel'}';

    return Semantics(
      label: label,
      button: widget.tappable,
      selected: widget.selected,
      excludeSemantics: true,
      child: FadeTransition(
        opacity: _appear.drive(Tween(begin: 0.0, end: 1.0)),
        child: ScaleTransition(
          scale: _appear.drive(Tween(begin: 0.5, end: 1.0)),
          child: ScaleTransition(
            scale: _scale,
            child: _withMark(
              c,
              AnimatedContainer(
                key: ValueKey('tile-${date.month}-${date.day}'),
                duration: context.motion(Motion.theme),
                height: widget.height,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: half ? null : bg,
                  gradient: half
                      ? LinearGradient(
                          begin: Alignment.bottomLeft,
                          end: Alignment.topRight,
                          colors: [bg, bg, c.empty, c.empty],
                          stops: const [0, 0.5, 0.5, 1],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(Radii.tile),
                  border: widget.selected
                      ? Border.all(color: c.text, width: 2.5)
                      : muted
                      ? Border.all(color: festiveLine, width: 1.5)
                      : widget.future
                      ? Border.all(color: c.line)
                      : null,
                ),
                // Con cifra, el número va encima y la cifra debajo. El día 1
                // va sin el mes: ya lo dice el título (013, RF-18).
                child: caption != null
                    ? Padding(
                        padding: const EdgeInsets.all(Space.xs / 2),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${date.day}',
                                style: AppText.caption.copyWith(
                                  color: fg,
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                caption,
                                style: AppText.label.copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Text(
                        '${date.day}',
                        style: AppText.label.copyWith(color: fg),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// El detalle va en la esquina, sobre un disco del color de la superficie
  /// para que se vea sobre cualquier relleno sin tapar el número (013, RF-9).
  Widget _withMark(AppColors c, Widget tile) {
    final mark = widget.mark;
    if (mark == null) return tile;
    return Stack(
      children: [
        tile,
        Positioned(
          top: 2,
          right: 2,
          child: Container(
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
            child: DayMarkIcon(mark: mark),
          ),
        ),
      ],
    );
  }
}
