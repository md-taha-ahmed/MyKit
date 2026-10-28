/// Case-insensitive "natural" comparison: numbers compare by value, so
/// "Track 2" < "Track 10".
int naturalCompare(String a, String b) {
  final ta = _tokens(a.toLowerCase());
  final tb = _tokens(b.toLowerCase());
  for (var i = 0; i < ta.length && i < tb.length; i++) {
    final x = ta[i], y = tb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null)
        ? (nx != ny ? nx.compareTo(ny) : x.length.compareTo(y.length))
        : x.compareTo(y);
    if (c != 0) return c;
  }
  return ta.length.compareTo(tb.length);
}

final _chunk = RegExp(r'\d+|\D+');

List<String> _tokens(String s) =>
    _chunk.allMatches(s).map((m) => m.group(0)!).toList();
