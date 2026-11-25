import 'package:flutter/material.dart';

import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

/// Sección de Ayuda de la app. Se amplía con cada cambio visible.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _topics = [
    (
      'Empresa y antigüedad',
      'En Ajustes › Empresa pones el nombre de tu empresa y tu fecha de '
          'alta (la de tu vida laboral), los dos opcionales. Debajo de la '
          'fecha ves los días que llevas, contados como la Seguridad Social: '
          'días naturales desde el alta, con vacaciones, bajas y fines de '
          'semana. Compáralos con tu vida laboral para comprobar la fecha. '
          'Con la fecha puesta, arriba de Métricas sale tu antigüedad en años, '
          'meses y días. Va en las copias. Para quitar un dato, toca la ✕; '
          'puedes deshacerlo.',
    ),
    (
      'Métricas',
      'Cómo van tus horas extra a lo largo del tiempo, con las horas y sus '
          'euros a la vez. Arriba eliges un año (con flechas) o «Todos los '
          'años»; también puedes deslizar el dedo para pasar de una a otra. '
          'Cada hora cuenta en el mes en que la hiciste. En un año ves '
          'el total, la comparación con el año anterior hasta la misma fecha, '
          'una barra por mes (tócala para ver su cifra; la barra fina es el '
          'mismo mes del año anterior), la media de los meses terminados, una '
          'estimación de fin de año, las horas por día de la semana y los '
          'días laborables con horas extra. En «Todos los años», el total '
          'desde el principio, las medias, los récords, la evolución (una '
          'barra por mes y la línea de la media de los últimos 12 meses, que '
          'enseña la tendencia; desliza el dedo sobre ella para ver cada mes) '
          'y la lista de años, con trofeos de oro, plata y bronce para los '
          'tres con más horas: toca uno '
          'para abrirlo. Los euros son los de Resumen y se ocultan con el '
          'ojo; si unas horas son de antes de tu primera tarifa, se cuentan '
          'con esa y llevan «aprox.». Si pones tu empresa en Ajustes, arriba '
          'ves tu antigüedad.',
    ),
    (
      'Apuntar horas',
      'Al abrir la app ya estás en Hoy. Toca dos veces las horas que has '
          'hecho: el primer toque las marca («Toca otra vez para apuntar») y '
          'el segundo las guarda, lo que confirma «✓ Apuntado». Así un toque '
          'sin querer no apunta nada; la marca se quita sola a los 3 '
          'segundos. Si apuntas otro botón, ese pasa a ser el total del día: '
          'no se suman. Para más de 5 '
          'horas o una cantidad distinta, toca «Otra», gira la rueda hasta la '
          'cifra y toca «Apuntar». Debajo de los botones ves cuánto vas a '
          'cobrar ese mes, ya restadas las horas que hayas apartado.',
    ),
    (
      'Otro día',
      'Arriba eliges Hoy, Ayer o Anteayer; también puedes deslizar el dedo: '
          'hacia la izquierda vas al día anterior y hacia la derecha vuelves '
          'a Hoy. Para un día más antiguo, toca '
          '«Otro día»: el calendario enseña cada día con horas en su color y '
          'con sus horas, y arriba el total del mes. Los sábados, domingos y '
          'festivos llevan el borde en coral. Cambia de mes con las '
          'flechas, o toca el nombre del mes para saltar a otro mes o año, y '
          'toca el día. No se puede apuntar en días que aún no han '
          'llegado.',
    ),
    (
      'Normal o festiva',
      'Los sábados y domingos se proponen como festivos. Si un día es festivo '
          'por otro motivo, toca el botón del tipo para cambiarlo. Cada día '
          'guarda su tipo, aunque más adelante cambie la lista de festivos.',
    ),
    (
      'Tarifas',
      'En Ajustes → Tarifas pones los euros por hora de las horas normales y de '
          'las festivas. Cada tarifa sale con su periodo («del 1 ene 2021 al '
          '31 dic 2025», o «desde el 1 ene 2026 · hasta hoy» la última). El '
          'final lo pone la app: el día antes de que empiece la siguiente, así '
          'no quedan días sin tarifa ni con dos. Cuando te suban, toca «Añadir '
          'tarifa nueva» y elige desde qué fecha vale; la anterior se cierra '
          'sola. Toca una tarifa para corregir su importe o su inicio, o para '
          'borrarla.',
    ),
    (
      'Secciones y Ajustes',
      'Abajo cambias entre Apuntar, Resumen, Vacaciones, Extra y Métricas. Ajustes (tarifas, '
          'festivos, copias, aspecto y esta ayuda) se abre con el engranaje de '
          'arriba a la derecha: en Apuntar está junto a la fecha. En Ajustes → '
          'Aspecto eliges tema Claro, Oscuro o Automático (el del móvil) y '
          'puedes apagar los calendarios temáticos: los dibujos de Navidad, '
          'Reyes, Carnaval, Halloween, San Juan, la Semana Grande y las '
          'estaciones junto al nombre del mes.',
    ),
    (
      'Resumen y meses',
      'La sección Resumen enseña arriba «A cobrar» (horas = euros de los '
          'meses aún sin cobrar) con su cuenta. Debajo, en un recuadro, lo que '
          'te deben de los meses ya entregados, también con su cuenta. En las '
          'dos cuentas: horas normales × su tarifa y '
          'festivas × la suya (si cambió la tarifa, una línea por cada una; si '
          'el redondeo de cada mes mueve un céntimo, sale en su línea). Luego la '
          'lista de meses, agrupados por años en tarjetas con su resumen: el '
          'año en curso sale desplegado y los anteriores, plegados; toca una '
          'tarjeta para plegarla o desplegarla. Cada mes pasa por '
          'Abierto (reloj), Entregado (sobre: el papel ya está entregado) y '
          'Cobrado (✓); si hay meses sin entregar o entregados sin cobrar, '
          'te avisa. Toca un mes para ver su Hoja y cambiar el '
          'estado. Si te pagan varios meses juntos, usa «Cobrar varios meses». '
          'El importe de cada mes se redondea una sola vez al céntimo. Si hay horas '
          'anteriores a tu primera tarifa, avisa y no las cuenta. El ojo de arriba '
          'oculta todos los importes.',
    ),
    (
      'Multas y extras',
      'En la sección Extra apuntas el dinero que no son horas: las multas que en '
          'teoría debes a la empresa (restan, en rojo) y los extras que te debe '
          'aparte de las horas (suman, en turquesa). Toca «Añadir», elige Multa o '
          'Extra y escribe importe, concepto y fecha. Toca uno para cambiarlo, '
          'cambiar su estado (una multa se descuenta o se anula; un extra se '
          'cobra o se descarta) o borrarlo. En una multa puedes encender «Pronto '
          'pago (−50 %)», y entonces cuenta la mitad (en la lista sale el '
          'importe completo tachado), y «La paga la empresa», y entonces no '
          'resta. La primera multa de cada año lleva la marca «Primera del '
          'año», porque en teoría la paga la empresa; enciende el interruptor '
          'solo cuando lo confirmes. Nunca se mezclan con «A cobrar»: en Resumen tienes aparte «Con multas y extras», que suma los '
          'extras y resta las multas aún pendientes. Es un total posible, sin '
          'confirmar. Extra tiene dos pestañas: «Multas y extras» y «Horas '
          'guardadas»; cambias de una a otra tocándolas o deslizando el dedo.',
    ),
    (
      'Horas guardadas',
      'Son las horas que no cobras en su mes porque las guardas para más '
          'adelante, en dos cajones: la Bolsa de empresa (edificio) y Mi reserva '
          '(hucha). Están en la pestaña «Horas guardadas» de Extra; en Resumen, '
          'la línea «Horas guardadas» enseña lo que hay y lo que valdría a tu '
          'tarifa normal de hoy, y al tocarla te lleva allí. Con «Añadir» '
          'eliges uno de estos: «Horas de antes» (las que ya tenías, no tocan '
          'ningún mes), «Apartar» (se restan de las horas normales del mes de la '
          'fecha, que debe estar Abierto), «Tiempo libre» (te las devuelven en '
          'días u horas libres; te recuerda la jornada de 39 h y el botón «Día '
          'completo» pone 8 h de lunes a jueves o 7 h el viernes, según la '
          'fecha) o «Cobrar» (te las pagan a la tarifa normal de '
          'ese día; el importe queda fijo). No puedes sacar más de lo que hay. '
          'Su valor es posible, sin confirmar, y no se suma a ningún otro total.',
    ),
    (
      'Cambiar horas por tiempo libre',
      'Si te dan tiempo libre a cambio de horas de un mes y no quieres pasar '
          'por un cajón, abre el mes en Resumen y toca «Cambiar horas por '
          'tiempo libre» (o elige «Cambio por libre» al añadir en Horas '
          'guardadas). Las horas se restan del mes de la fecha, igual que al '
          'apartar, pero ningún cajón sube ni baja: suman en «Compensadas». '
          'Puedes anotar el día libre, solo para recordarlo. En Resumen, cada '
          'mes dice cuántas horas se apartaron o se cambiaron, y en Apuntar la '
          'línea del dinero dice cuántas horas quedan fuera.',
    ),
    (
      'Vacaciones',
      'Primero, en Ajustes → Vacaciones, di desde qué año llevas la cuenta, '
          'cuántos días tuviste ese año y cuántos te corresponden cada año '
          '(se generan de golpe el 1 de enero). Si algún año fue distinto, '
          'tócalo para corregirlo. En la sección Vacaciones, toca un día del '
          'calendario para marcarlo y otra vez para quitarlo (con «Deshacer»). '
          'Los sábados, domingos y festivos no gastan días. Puedes planificar '
          'hasta el final del año que viene. Cada día pertenece a un año: los '
          'de enero cuentan para el año anterior si a ese año aún le quedan '
          'días, y se ven con «’25». Mantén pulsado un día marcado para '
          'hacerlo medio día (se ve a medias, con «½», y gasta 0,5) o para '
          'cambiar su año. Toca el nombre del mes para saltar a otro mes o año. Los '
          'sábados, domingos y festivos llevan el borde en coral y los días de '
          'vacaciones van en amarillo. Abajo tienes dos vistas: «Por año de vacaciones» (lo generado, '
          'lo disfrutado y lo que queda de cada año; «Años anteriores» lleva su '
          'suma, así lo que ves siempre cuadra con el total) y «Por año '
          'natural» (los '
          'días que disfrutaste cada año). En Apuntar verás «Vacaciones» en '
          'esos días, y en Resumen, cuántos te quedan.',
    ),
    (
      'Festivos',
      'Los sábados, los domingos y los festivos se proponen como «Festiva». '
          'En Ajustes → «Festivos» vienen los 10 nacionales (Viernes Santo se '
          'calcula solo); si alguno no te corresponde, desactívalo. Los de tu '
          'comunidad, los dos locales de tu municipio y los traslados los '
          'añades tú en «Los míos»: cada año, si se repiten en la misma fecha, '
          'o solo ese año, si cambian (como Jueves Santo). Búscalos en el '
          'calendario laboral de tu comunidad y en la web de tu ayuntamiento. '
          'Los días ya apuntados no cambian.',
    ),
    (
      'Motivo',
      'Cuando el día ya tiene horas, puedes escribir un motivo (hasta 60 '
          'letras). Se guarda solo al dejar de escribir y lo confirma con un ✓. '
          'Mientras escribes, '
          'te sugiere los motivos que ya has usado.',
    ),
    (
      'Borrar y deshacer',
      'Toca dos veces el botón de horas que está resaltado para borrar el '
          'día entero: horas, tipo y motivo (el primer toque lo marca en coral: '
          '«Toca otra vez para borrar»). Si apuntaste con «Otra», tócala y '
          'pulsa «Borrar». Durante 5 segundos puedes tocar «Deshacer» en el '
          'aviso de abajo y el día vuelve tal como estaba.',
    ),
    (
      'Resumen del mes',
      'Abajo ves las horas del mes del día elegido: el total, las normales y '
          'las festivas, y lo que vas a cobrar ese mes.',
    ),
    (
      'Meses del Excel',
      'Los años anteriores vienen del Excel solo como el total de cada mes '
          '(normales y festivas), sin días: cuentan en Resumen y en Métricas, '
          'pero no salen en los calendarios ni en las horas por día de la '
          'semana. Su importe usa la tarifa del día 1 de ese mes. En esos '
          'meses no se pueden apuntar días, para no contar dos veces.',
    ),
    (
      'Copias',
      'Para no perder tus horas, la app hace copias sola en una carpeta que '
          'eliges tú (Ajustes → «Copias y exportación»). '
          'Se hace una copia al salir de la app, si has cambiado algo desde la '
          'última. Cada copia lleva el nombre de este móvil, que puedes '
          'cambiar allí mismo. Guarda las 10 más recientes de este móvil y '
          'nunca borra otros archivos de esa carpeta, tampoco las copias de '
          'otro móvil. Si una copia falla, aparece un aviso «No se ha podido '
          'hacer la copia» con el botón «Revisar». «Hacer copia ahora» la hace '
          'al momento.',
    ),
    (
      'Dos móviles',
      'Puedes usar la app en dos móviles. En los dos, elige como carpeta de '
          'copias la misma carpeta, y sincronízala con Syncthing en modo '
          '«Enviar y recibir» en ambos. Al abrir la app, si el otro móvil '
          'tiene cambios más nuevos, Apuntar muestra «Hay cambios de…» con '
          'el botón «Ver»: verás qué cambia y podrás cargarlos o dejarlo '
          'para luego. Se trabaja por turnos: cargar sustituye lo de este '
          'móvil por lo del otro, y antes guarda lo tuyo en una copia «antes '
          'de restaurar». Apunta en un móvil, sal de la app para que haga su '
          'copia y luego abre el otro. Los festivos que añadas tú no viajan '
          'en las copias: añádelos en los dos.',
    ),
    (
      'Primeros pasos',
      'Al empezar, arriba de Resumen sale una tarjeta con lo que conviene '
          'preparar: tus tarifas, tus vacaciones, los festivos de tu zona y '
          'una copia. Toca cada línea para ir a su ajuste; se marca sola '
          'cuando está hecho. Cuando están las cuatro, o si pulsas '
          '«Ocultar», la tarjeta desaparece para siempre.',
    ),
    (
      'Compartir copia',
      'Si no quieres usar una carpeta, en Ajustes → «Copias y exportación» '
          'pulsa «Compartir copia»: hace una copia completa y abre el menú '
          'Compartir del móvil para guardarla en Google Drive, mandártela por '
          'correo, etc. Para recuperarla: «Restaurar una copia» → «Elegir '
          'otro archivo…» y elígela donde la guardaste (sin carpeta, solo con '
          'la app vacía, como en un móvil nuevo). La app no sabe si llegaste '
          'a guardarla: si no tienes carpeta, Apuntar te recuerda compartir '
          'una copia cada 15 días.',
    ),
    (
      'Restaurar una copia',
      'En «Copias y exportación» toca «Restaurar una copia» y elige una de la '
          'lista: ves su fecha, de qué móvil es y cuántos días con horas '
          'tiene. Antes de '
          'sustituir tus datos, la app guarda una copia de lo que tienes ahora '
          '(«antes de restaurar»), que no se borra sola. Si has reinstalado la '
          'app, elige la carpeta y restaura, o usa «Elegir otro archivo…» para '
          'buscar un archivo de copia.',
    ),
    (
      'Exportar a Excel',
      'Toca «Exportar a Excel» para crear un archivo CSV con todos tus días: '
          'fecha, horas (con coma, p. ej. 2,5), minutos exactos, tipo y motivo. '
          'Debajo, tras una línea vacía, van las multas y los extras. '
          'Se guarda en la carpeta de copias y se abre el menú de compartir. '
          'Ábrelo con Excel; si no sale bien, usa Datos → Desde texto o CSV.',
    ),
    (
      'Llevar las copias al ordenador (Syncthing)',
      'Syncthing es una app gratuita que sincroniza carpetas entre el móvil y '
          'el ordenador sin pasar por internet de nadie. Instálala en los dos, '
          'añade en el móvil la carpeta de las copias y compártela con el '
          'ordenador. Si solo usas un móvil, pon allí la carpeta en modo «Solo '
          'enviar»: así lo que pase en el ordenador nunca podrá cambiar ni '
          'borrar tus copias. Si usas dos móviles, en ellos va en «Enviar y '
          'recibir» (mira «Dos móviles») y en el ordenador, en «Solo '
          'recibir».',
    ),
    (
      'Tus datos',
      'Todo se guarda en tu móvil; la app no usa internet. Solo salen de él las '
          'copias y el CSV que mandas tú a la carpeta o a la app que eliges. Si '
          'algo no se puede guardar, la app te lo dice y deja lo último que se '
          'guardó bien.',
    ),
    (
      'Colores y tema',
      'Turquesa para las horas normales y coral para las festivas. La app '
          'sigue el tema claro u oscuro del móvil y, si tienes las animaciones '
          'reducidas, también las quita. En Ajustes → Aspecto eliges '
          'automático, claro u oscuro.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.s,
          Space.gutter,
          Space.xxxl,
        ),
        children: [
          for (final (title, text) in _topics)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(title, style: AppText.title),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(text, style: AppText.body.copyWith(color: c.text)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
