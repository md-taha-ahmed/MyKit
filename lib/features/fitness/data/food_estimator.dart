import 'dart:convert';

import '../../../core/ai/gemini_client.dart';
import '../../../core/i18n/i18n.dart';

/// One food the estimate found.
typedef EstimatedItem = ({String name, String amount, int kcal});

class FoodEstimate {
  const FoodEstimate({required this.items, this.note = ''});

  final List<EstimatedItem> items;

  /// Assumptions (portion sizes, oil…).
  final String note;

  int get total => items.fold(0, (s, i) => s + i.kcal);
}

/// Estimates calories from a description and/or a photo with Gemini. One
/// short request per meal, only when asked (free plan friendly).
class FoodEstimator {
  FoodEstimator(this._gemini);

  final GeminiClient _gemini;

  static const _system = '''
You estimate the calories of a meal for a calorie counter. You know home cooking across the Arab world and especially Yemen (saltah, fahsa, bint al-sahn, malawah, lahoh, mandi, haneeth, aseed, fatoot, shafoot, zurbian, Yemeni tea with milk and sugar…), plus common international foods.

Rules:
- Split the meal into its foods. For each, give a realistic home portion ("2 pieces", "1 bowl ~300 g") and calories for that portion. Count cooking oil, ghee and sugar, which are often large in home cooking.
- If a photo is given, judge portions from it (plate size, hands, cutlery).
- If the user states amounts, use them.
- Be honest: these are estimates. Put your main assumptions in "note" (one or two short sentences).
- Food names and notes in the user's language.
Reply with JSON only, no other text:
{"items":[{"name":"...","amount":"...","kcal":123}],"note":"..."}
''';

  Future<FoodEstimate> estimate({
    String text = '',
    AiImage? photo,
    required bool arabic,
  }) async {
    final ask = [
      if (text.trim().isNotEmpty) 'Meal: ${text.trim()}',
      if (photo != null) 'Estimate the meal in this photo.',
      arabic ? 'Answer in Arabic.' : 'Answer in English.',
    ].join('\n');
    final reply = await _gemini.generate(
      system: _system,
      messages: [(fromUser: true, text: ask)],
      temperature: 0.2,
      image: photo,
    );
    return parse(reply);
  }

  static FoodEstimate parse(String reply) {
    final start = reply.indexOf('{');
    final end = reply.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw AiException(tr('Could not read the estimate. Try again.'));
    }
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(reply.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      throw AiException(tr('Could not read the estimate. Try again.'));
    }
    final items = <EstimatedItem>[
      for (final i in (j['items'] as List?) ?? const [])
        if (i is Map && i['kcal'] is num)
          (
            name: '${i['name'] ?? ''}'.trim(),
            amount: '${i['amount'] ?? ''}'.trim(),
            kcal: (i['kcal'] as num).round().clamp(0, 5000),
          ),
    ];
    if (items.isEmpty) {
      throw AiException(tr('No food found. Describe it a little more.'));
    }
    return FoodEstimate(items: items, note: '${j['note'] ?? ''}'.trim());
  }
}
