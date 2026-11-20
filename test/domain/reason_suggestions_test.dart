import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/reason_suggestions.dart';

void main() {
  // Motivos inventados con las veces que se han usado.
  const used = {
    'Taller Norte': 7,
    'Inventario': 3,
    'Montaje feria': 5,
    'Revisión camión': 2,
    'Taller Sur': 1,
  };

  test(
    'sugiere los que contienen lo escrito, los más usados primero (RF-16)',
    () {
      expect(suggestReasons('tall', used), ['Taller Norte', 'Taller Sur']);
    },
  );

  test('no distingue mayúsculas ni tildes', () {
    expect(suggestReasons('REVISION', used), ['Revisión camión']);
    expect(suggestReasons('camion', used), ['Revisión camión']);
    expect(suggestReasons('Revisión', used), ['Revisión camión']);
  });

  test('busca también en mitad del texto', () {
    expect(suggestReasons('feria', used), ['Montaje feria']);
  });

  test('como mucho 5 sugerencias', () {
    final many = {for (var i = 0; i < 9; i++) 'Obra $i': i + 1};
    final s = suggestReasons('obra', many);
    expect(s.length, 5);
    expect(s.first, 'Obra 8');
  });

  test('sin texto, o con solo espacios, no sugiere nada', () {
    expect(suggestReasons('', used), isEmpty);
    expect(suggestReasons('   ', used), isEmpty);
  });

  test('no sugiere lo mismo que ya está escrito', () {
    expect(suggestReasons('taller norte', used), isEmpty);
  });

  test('junta las variantes del mismo motivo y deja la más usada', () {
    const variants = {'Taller norte': 2, 'Taller Norte': 5, 'Inventario': 6};
    expect(suggestReasons('tall', variants), ['Taller Norte']);
    // Las variantes suman sus usos: 7 veces pasan por delante de 6.
    expect(suggestReasons('r', variants), ['Taller Norte', 'Inventario']);
  });

  test('a igual uso, orden alfabético', () {
    const tie = {'Beta obra': 2, 'Alfa obra': 2};
    expect(suggestReasons('obra', tie), ['Alfa obra', 'Beta obra']);
  });

  test('quitar tildes conserva la ñ', () {
    expect(foldForSearch('Año ÁÉÍÓÚ ü'), 'año aeiou u');
  });
}
