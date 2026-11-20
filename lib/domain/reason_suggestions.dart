/// Sugerencias para el motivo a partir de los que ya se han usado (RF-16).
library;

/// Como mucho, cuántas sugerencias se muestran.
const maxSuggestions = 5;

const _plain = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
}; // la ñ se conserva: es otra letra, no una tilde

/// Minúsculas y sin tildes, para comparar.
String foldForSearch(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    out.write(_plain[ch] ?? ch);
  }
  return out.toString();
}

/// Los motivos de [usage] (motivo → veces usado) que contienen [query], sin
/// distinguir mayúsculas ni tildes: los más usados primero y, a igualdad,
/// por orden alfabético. Las variantes de un mismo motivo («Taller norte» y
/// «Taller Norte») se juntan con la forma más usada. No se sugiere lo que ya
/// está escrito tal cual.
List<String> suggestReasons(String query, Map<String, int> usage) {
  final q = foldForSearch(query.trim());
  if (q.isEmpty) return const [];

  final total = <String, int>{}; // forma simplificada → usos
  final best = <String, String>{}; // forma simplificada → forma más usada
  final bestUses = <String, int>{};
  usage.forEach((reason, uses) {
    final key = foldForSearch(reason.trim());
    if (key.isEmpty) return;
    total[key] = (total[key] ?? 0) + uses;
    if (uses > (bestUses[key] ?? -1)) {
      best[key] = reason.trim();
      bestUses[key] = uses;
    }
  });

  final keys = total.keys.where((k) => k != q && k.contains(q)).toList()
    ..sort((a, b) {
      final byUse = total[b]!.compareTo(total[a]!);
      return byUse != 0 ? byUse : a.compareTo(b);
    });
  return [for (final k in keys.take(maxSuggestions)) best[k]!];
}
