import 'package:flutter/widgets.dart';

// Hebrew, Arabic, Syriac, Thaana, NKo… and the Arabic presentation forms.
final _rtl = RegExp('[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');
final _ltr = RegExp('[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]');
final _space = RegExp(r'\s+');

/// Right-to-left when most words at the start of [text] are RTL (Arabic,
/// Hebrew…). Counting words, not letters, so Latin brand names and numbers
/// in an Arabic headline don't flip it.
TextDirection textDirectionOf(String text) {
  final sample = text.length > 400 ? text.substring(0, 400) : text;
  var rtl = 0, ltr = 0;
  for (final word in sample.split(_space)) {
    if (_rtl.hasMatch(word)) {
      rtl++;
    } else if (_ltr.hasMatch(word)) {
      ltr++;
    }
  }
  return rtl > 0 && rtl >= ltr ? TextDirection.rtl : TextDirection.ltr;
}

bool isRtlText(String text) => textDirectionOf(text) == TextDirection.rtl;

/// Lays [child] out in the direction of [text] (alignment, row order,
/// bullets), so Arabic articles read right-to-left in a left-to-right app.
class AutoDirection extends StatelessWidget {
  const AutoDirection({super.key, required this.text, required this.child});

  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: textDirectionOf(text), child: child);
}
