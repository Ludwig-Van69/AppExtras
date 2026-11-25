# Extras

App Android para apuntar horas extra con un toque y llevar la cuenta de lo que se debe: meses entregados y cobrados, tarifas por periodos, multas y extras, horas guardadas, vacaciones, métricas y antigüedad en la empresa.

Hecha con Flutter (Dart) y SQLite. Los datos se guardan solo en el móvil, con copia automática en una carpeta que eliges o compartida a donde quieras.

## Compilar

```
flutter pub get
flutter test
flutter build apk --release
```

Para firmar la versión de publicación hace falta un `android/key.properties` propio (no está en el repositorio).

## Festivos

Trae los 10 festivos nacionales de España. Los de tu comunidad, los locales de tu municipio y los traslados se añaden desde la app, en Ajustes › Festivos › «Los míos».

## Copias

Además de la copia automática en una carpeta, «Compartir copia» manda una copia completa a Drive, al correo, etc., desde el menú Compartir del móvil. La app no pide permiso de internet.

## Dos móviles

Cada copia lleva el nombre del móvil que la hizo. Si dos móviles eligen la misma carpeta y la sincronizan (por ejemplo con Syncthing), al abrir la app en uno se avisa de los cambios del otro, se ve qué cambia por apartados y se decide si cargarlos.
