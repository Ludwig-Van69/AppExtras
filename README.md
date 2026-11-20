# Extras

App Android para apuntar horas extra con un toque y llevar la cuenta de lo que se debe: meses entregados y cobrados, tarifas por periodos, multas y extras, horas guardadas, vacaciones y métricas.

Hecha con Flutter (Dart) y SQLite. Los datos se guardan solo en el móvil, con copia automática en una carpeta que eliges.

## Compilar

```
flutter pub get
flutter test
flutter build apk --release
```

Para firmar la versión de publicación hace falta un `android/key.properties` propio (no está en el repositorio).

## Festivos

Trae los festivos nacionales de España. Los autonómicos y locales van en `lib/domain/local_holidays.dart`, que aquí está vacío: añade los de tu zona. Desde la app también se pueden añadir a mano.
