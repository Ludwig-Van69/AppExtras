import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/metrics.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';

/// Datos inventados. Hoy: miércoles 18 de noviembre de 2026.
final _today = DateTime(2026, 11, 18, 10);
final _rates = [
  Rate(DayKind.normal, DateTime(2020), 1500),
  Rate(DayKind.festive, DateTime(2020), 2000),
];

DayEntry _e(int y, int m, int d, int minutes, [DayKind k = DayKind.normal]) =>
    DayEntry(date: DateTime(y, m, d), minutes: minutes, kind: k);

List<MonthLine> _lines(
  List<DayEntry> entries, {
  List<Rate>? rates,
  List<SavedMove> saved = const [],
}) => MoneyOverview.compute(
  entries: entries,
  rates: rates ?? _rates,
  records: const [],
  savedMoves: saved,
).months;

SavedMove _setAside(DateTime date, int minutes) => SavedMove(
  box: SavedBox.own,
  kind: SavedMoveKind.setAside,
  date: date,
  minutes: minutes,
);

YearMetrics _y(
  List<DayEntry> entries, {
  int year = 2026,
  List<Rate>? rates,
  List<SavedMove> saved = const [],
  DateTime? today,
  bool Function(DateTime)? isHoliday,
  bool Function(DateTime)? isVacation,
}) => computeYearMetrics(
  months: _lines(entries, rates: rates, saved: saved),
  rates: rates ?? _rates,
  year: year,
  today: today ?? _today,
  isHoliday: isHoliday,
  isVacation: isVacation,
);

GlobalMetrics _g(List<DayEntry> entries, {List<Rate>? rates}) =>
    computeGlobalMetrics(
      months: _lines(entries, rates: rates),
      rates: rates ?? _rates,
      today: _today,
    );

void main() {
  group('podio de años (018, RF-6)', () {
    YearRow y(int year, int hours) => YearRow(year, Figure(hours * 60, 0));

    test('oro, plata y bronce; el cuarto sin trofeo', () {
      expect(podium([y(2026, 10), y(2025, 40), y(2024, 30), y(2023, 20)]), {
        2025: 1,
        2024: 2,
        2023: 3,
      });
    });

    test('con empate gana el más reciente', () {
      expect(podium([y(2026, 30), y(2025, 30), y(2024, 10)]), {
        2026: 1,
        2025: 2,
        2024: 3,
      });
    });

    test('con un solo año, ningún trofeo; con dos, oro y plata', () {
      expect(podium([y(2026, 30)]), isEmpty);
      expect(podium([y(2026, 30), y(2025, 0)]), isEmpty);
      expect(podium([y(2026, 30), y(2025, 40)]), {2025: 1, 2026: 2});
    });
  });

  group('un año', () {
    test('cada mes es una barra con horas y euros, y el mismo mes del año '
        'anterior (014, criterio 1; 015, RF-3)', () {
      final m = _y([_e(2026, 3, 10, 600), _e(2025, 3, 12, 480)]);
      expect(m.bars, hasLength(12));
      final march = m.bars[2];
      expect(march.month, const YearMonth(2026, 3));
      expect(march.figure, const Figure(600, 15000));
      expect(march.previous!.minutes, 480);
      expect(m.bars[10].isCurrent, isTrue);
    });

    test('sin datos del año anterior no hay barra suave ni comparación', () {
      final m = _y([_e(2026, 3, 10, 600)]);
      expect(m.bars[2].previous, isNull);
      expect(m.comparison, isNull);
    });

    test('los euros de cada mes coinciden al céntimo con Resumen (014, '
        'criterio 2)', () {
      final entries = [
        _e(2026, 11, 2, 95),
        _e(2026, 11, 7, 125, DayKind.festive),
        _e(2026, 11, 9, 35),
      ];
      final saved = [_setAside(DateTime(2026, 11, 3), 30)];
      final m = _y(entries, saved: saved);
      final nov = _lines(
        entries,
        saved: saved,
      ).firstWhere((l) => l.month == const YearMonth(2026, 11));
      expect(m.bars[10].figure.cents, nov.amountCents);
      expect(m.total.cents, nov.amountCents);
      expect(m.normal.cents + m.festive.cents, m.total.cents);
      expect(m.festive.cents, nov.amountOf(DayKind.festive));
      expect(m.total.approx, isFalse);
    });

    test('en horas cuenta también lo apartado (014, RF-5)', () {
      final m = _y(
        [_e(2026, 11, 2, 120)],
        saved: [_setAside(DateTime(2026, 11, 3), 60)],
      );
      expect(m.total.minutes, 120);
      expect(m.total.cents, 1500);
    });

    test('antes de la primera tarifa, se usa esa y es aproximado (015, '
        'RF-5, criterio 4)', () {
      final m = _y(
        [_e(2023, 5, 4, 60)],
        year: 2023,
        rates: [Rate(DayKind.normal, DateTime(2024), 1500)],
      );
      expect(m.total.cents, 1500);
      expect(m.total.approx, isTrue);
      expect(m.total.missing, isFalse);
    });

    test('sin ninguna tarifa de su tipo, los euros faltan', () {
      final m = _y(
        [_e(2026, 5, 2, 60, DayKind.festive)],
        rates: [Rate(DayKind.normal, DateTime(2024), 1500)],
      );
      expect(m.total.cents, 0);
      expect(m.total.missing, isTrue);
    });

    test('total con el reparto entre normales y festivas', () {
      final m = _y([_e(2026, 2, 2, 120), _e(2026, 2, 7, 300, DayKind.festive)]);
      expect(m.total, const Figure(420, 13000));
      expect(m.normal, const Figure(120, 3000));
      expect(m.festive, const Figure(300, 10000));
    });

    test('la media no cuenta el mes en curso ni los anteriores al primer '
        'dato (014, criterio 5)', () {
      final m = _y([
        _e(2026, 9, 1, 600),
        _e(2026, 10, 1, 300),
        _e(2026, 11, 2, 900),
      ]);
      expect(m.average, const Figure(450, 11250));
    });

    test('sin meses terminados no hay media', () {
      expect(_y([_e(2026, 11, 2, 120)]).average, isNull);
    });

    test('la comparación suma de enero al 18 de noviembre en los dos años '
        '(014, criterio 6)', () {
      final m = _y([
        _e(2026, 1, 5, 60),
        _e(2026, 11, 18, 120),
        _e(2025, 1, 5, 30),
        _e(2025, 11, 18, 60),
        _e(2025, 11, 19, 600), // después del 18: no cuenta
      ]);
      final c = m.comparison!;
      expect(c.current.minutes, 180);
      expect(c.previous.minutes, 90);
      expect(c.difference.minutes, 90);
      expect(c.difference.cents, 2250);
      expect(c.until, DateTime(2026, 11, 18));
    });

    test('en un año terminado se comparan los años enteros', () {
      final m = _y([_e(2025, 12, 30, 60), _e(2024, 12, 30, 120)], year: 2025);
      expect(m.comparison!.current.minutes, 60);
      expect(m.comparison!.previous.minutes, 120);
      expect(m.comparison!.until, isNull);
    });

    test('la comparación resta lo apartado hasta esa fecha', () {
      final m = _y(
        [_e(2026, 11, 2, 60), _e(2025, 11, 2, 120)],
        saved: [
          _setAside(DateTime(2025, 11, 10), 60),
          _setAside(DateTime(2025, 11, 20), 30),
        ],
      );
      expect(m.comparison!.previous.cents, 1500);
      expect(m.comparison!.current.cents, 1500);
    });

    test('previsión: solo en el año actual, desde febrero y redondeada '
        '(014, criterio 7)', () {
      final entries = [_e(2026, 1, 5, 600), _e(2026, 2, 2, 600)];
      expect(_y(entries, today: DateTime(2026, 1, 31)).forecast, isNull);
      expect(_y(entries, year: 2025).forecast, isNull);
      // 1-3-2026: día 60 de 365. 1200 min + 1200 × 305 / 60 = 7300 min
      // (121,67 h): 122 h. 300 € + 300 × 305 / 60 = 1825 €.
      final f = _y(entries, today: DateTime(2026, 3, 1)).forecast!;
      expect(f.minutes, 7320);
      expect(f.cents, 182500);
    });

    test('horas por día de la semana', () {
      final m = _y([
        _e(2026, 11, 2, 60), // lunes
        _e(2026, 11, 9, 90), // lunes
        _e(2026, 11, 8, 240, DayKind.festive), // domingo
      ]);
      expect(m.weekdayMinutes, [150, 0, 0, 0, 0, 0, 240]);
    });

    test('festivos y vacaciones no cuentan como laborables (014, '
        'criterio 8)', () {
      final holiday = DateTime(2026, 11, 2);
      final vacation = DateTime(2026, 11, 3);
      final m = _y(
        [
          _e(2026, 11, 2, 60), // festivo: no cuenta
          _e(2026, 11, 4, 60),
          _e(2026, 11, 7, 60), // sábado: no cuenta
        ],
        isHoliday: (d) => d == holiday,
        isVacation: (d) => d == vacation,
      );
      var weekdays = 0;
      for (
        var d = DateTime(2026);
        !d.isAfter(DateTime(2026, 11, 18));
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        if (d.weekday <= DateTime.friday) weekdays++;
      }
      expect(m.workdays, weekdays - 2);
      expect(m.workdaysWithHours, 1);
    });

    test('sin horas en el año', () {
      expect(_y([_e(2024, 3, 1, 60)]).empty, isTrue);
      expect(_y([_e(2026, 3, 1, 60)]).empty, isFalse);
    });
  });

  group('todos los años (015)', () {
    final entries = [
      _e(2024, 6, 3, 600),
      _e(2024, 7, 1, 300, DayKind.festive),
      _e(2025, 3, 3, 1200),
      _e(2025, 9, 1, 120),
      _e(2026, 2, 2, 480),
      _e(2026, 11, 2, 60),
    ];

    test('total global con normales y festivas (RF-7)', () {
      final g = _g(entries);
      expect(g.total.minutes, 2760);
      expect(g.festive.minutes, 300);
      expect(g.normal.minutes, 2460);
      // 2460 min a 15 €/h = 615 €; 300 min a 20 €/h = 100 €.
      expect(g.total.cents, 71500);
      expect(g.festive.cents, 10000);
    });

    test('medias: solo años y meses terminados (RF-8)', () {
      final g = _g(entries);
      // Años terminados: 2024 (900 min) y 2025 (1320 min).
      expect(g.averagePerYear!.minutes, 1110);
      // Meses terminados de junio de 2024 a octubre de 2026: 29, con
      // 2700 min (todo menos noviembre de 2026).
      expect(g.averagePerMonth!.minutes, 93); // 2700 / 29 = 93,1
    });

    test('récords: año y mes con más horas (RF-9)', () {
      final g = _g(entries);
      expect(g.bestYear!.year, 2025);
      expect(g.bestMonth!.month, const YearMonth(2025, 3));
    });

    test('con empate en el récord, gana el más reciente', () {
      final g = _g([_e(2024, 6, 3, 600), _e(2025, 6, 3, 600)]);
      expect(g.bestYear!.year, 2025);
      expect(g.bestMonth!.month, const YearMonth(2025, 6));
    });

    test('un punto por mes del primero al actual, vacíos a cero (RF-10, '
        'criterio 6)', () {
      final g = _g(entries);
      expect(g.series.first.month, const YearMonth(2024, 6));
      expect(g.series.last.month, const YearMonth(2026, 11));
      expect(g.series, hasLength(30));
      expect(g.series[1].figure.minutes, 300); // julio de 2024
      expect(g.series[2].figure, Figure.zero); // agosto de 2024
    });

    test('lista de años del más reciente al más antiguo (RF-11)', () {
      final g = _g(entries);
      expect(g.years.map((y) => y.year), [2026, 2025, 2024]);
      expect(g.years[1].figure.minutes, 1320);
    });

    test('sin horas, todo vacío (RF-12)', () {
      final g = _g([]);
      expect(g.empty, isTrue);
      expect(g.series, isEmpty);
      expect(g.bestYear, isNull);
    });

    test('primer año con horas', () {
      expect(firstMetricsYear(_lines([])), isNull);
      expect(firstMetricsYear(_lines(entries)), 2024);
    });

    test('la serie lleva la media de 12 meses desde el duodécimo (017, '
        'RF-3)', () {
      final g = _g(entries);
      expect(g.series[10].average, isNull);
      // Junio de 2024 a mayo de 2025: 600 + 300 + 1200 = 2100 min / 12.
      expect(g.series[11].month, const YearMonth(2025, 5));
      expect(g.series[11].average, 175);
    });
  });

  group('media móvil (017)', () {
    test('nula hasta tener la ventana y redondeada después', () {
      expect(movingAverage([1, 2, 3, 4], 3), [null, null, 2, 3]);
      expect(movingAverage([1, 2], 3), [null, null]);
      expect(movingAverage([], 12), isEmpty);
      // 14 meses: el 12.º es la media de los 12 primeros.
      final v = List.generate(14, (i) => (i + 1) * 60);
      final a = movingAverage(v, 12);
      expect(a[10], isNull);
      expect(a[11], 390); // (60 + … + 720) / 12
      expect(a[13], 510);
    });
  });
}
