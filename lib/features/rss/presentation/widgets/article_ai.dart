import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/ai/gemini_client.dart';
import '../../../../core/ai/gemini_key_screen.dart';
import '../../../../core/widgets/simple_markdown.dart';
import '../../rss_routes.dart';
import '../providers/article_ai_providers.dart';

const aiAccent = Color(0xFF8AB4F8);

/// "Summarize" / "Ask" buttons and, once requested, the summary itself.
class ArticleAiPanel extends ConsumerStatefulWidget {
  const ArticleAiPanel({super.key, required this.articleId});

  final String articleId;

  @override
  ConsumerState<ArticleAiPanel> createState() => _ArticleAiPanelState();
}

class _ArticleAiPanelState extends ConsumerState<ArticleAiPanel> {
  bool _show = false;

  Future<bool> _ensureKey() async {
    if (ref.read(geminiClientProvider).isConfigured) return true;
    await showGeminiKeyDialog(context, ref);
    return ref.read(geminiClientProvider).isConfigured;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: () async {
                if (await _ensureKey()) setState(() => _show = true);
              },
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(tr('Summarize')),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                if (await _ensureKey() && context.mounted) {
                  context.push(RssRoutes.articleChat(widget.articleId));
                }
              },
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text(tr('Ask')),
            ),
          ],
        ),
        if (_show) ...[
          const SizedBox(height: 12),
          _SummaryCard(articleId: widget.articleId),
        ],
      ],
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.articleId});

  final String articleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(articleSummaryProvider(articleId));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: aiAccent.withValues(alpha: 0.08),
        border: Border.all(color: aiAccent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: aiAccent),
              SizedBox(width: 6),
              Text(
                tr('Summary'),
                style: TextStyle(color: aiAccent, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          summary.when(
            loading: () => Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    tr('Reading the article…'),
                    style: TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
            error: (e, _) => Row(
              children: [
                Expanded(
                  child: Text(
                    '$e',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(articleSummaryProvider(articleId)),
                  child: Text(tr('Retry')),
                ),
              ],
            ),
            data: (text) => SimpleMarkdown(text),
          ),
        ],
      ),
    );
  }
}

/// The step-by-step Gemini key setup (shared with the rest of MyKit).
Future<void> showGeminiKeyDialog(BuildContext context, WidgetRef ref) =>
    openGeminiKeySetup(context);
