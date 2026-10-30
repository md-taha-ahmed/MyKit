import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/ai/gemini_client.dart';
import '../../../../core/utils/text_direction.dart';
import '../../../../core/widgets/simple_markdown.dart';
import '../providers/article_ai_providers.dart';
import '../providers/rss_providers.dart';
import '../widgets/article_ai.dart';

/// Ask Gemini about one article. The article and a researched background
/// briefing are prepared as soon as the screen opens; the conversation is
/// kept in memory until MyKit is closed.
class ArticleChatScreen extends ConsumerStatefulWidget {
  const ArticleChatScreen({super.key, required this.articleId});

  final String articleId;

  @override
  ConsumerState<ArticleChatScreen> createState() => _ArticleChatScreenState();
}

class _ArticleChatScreenState extends ConsumerState<ArticleChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  TextDirection _inputDirection = TextDirection.ltr;

  static const _suggestions = [
    'Explain it simply',
    'What\'s the background?',
    'Who are the main players?',
    'Why does this matter?',
  ];
  static const _suggestionsArabic = [
    'اشرح لي الخبر ببساطة',
    'ما خلفية هذا الموضوع؟',
    'من هي الأطراف الرئيسية؟',
    'لماذا هذا مهم؟',
  ];

  @override
  void initState() {
    super.initState();
    // Read the article and research the background while the user types.
    Future.microtask(
      () => ref.read(articleChatProvider(widget.articleId).notifier).prepare(),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    _input.clear();
    setState(() => _inputDirection = TextDirection.ltr);
    ref.read(articleChatProvider(widget.articleId).notifier).ask(text);
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final article = ref.watch(articleByIdProvider(widget.articleId));
    final chat = ref.watch(articleChatProvider(widget.articleId));
    final briefing = ref.watch(articleBriefingProvider(widget.articleId));
    ref.listen(articleChatProvider(widget.articleId), (prev, next) {
      // Follow a new question and the start of each answer; don't fight the
      // user scrolling back while a long answer streams in.
      if (prev?.turns.length != next.turns.length) _scrollToEnd();
    });
    final arabic = article != null && isRtlText(article.title);
    final lastAnswer = chat.turns.lastOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ask about this article'),
            if (article != null)
              Text(
                article.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: textDirectionOf(article.title),
                style: const TextStyle(fontSize: 12.5, color: Colors.white60),
              ),
          ],
        ),
        actions: [
          if (chat.turns.isNotEmpty)
            IconButton(
              tooltip: 'New conversation',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref
                  .read(articleChatProvider(widget.articleId).notifier)
                  .clear(),
            ),
          PopupMenuButton<String>(
            onSelected: (_) => showGeminiKeyDialog(context, ref),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'key', child: Text('Gemini API key…')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              children: [
                _BriefingCard(
                  briefing: briefing,
                  onRetry: () =>
                      ref.invalidate(articleBriefingProvider(widget.articleId)),
                ),
                if (chat.turns.isEmpty) ...[
                  const SizedBox(height: 20),
                  const Icon(Icons.auto_awesome, color: aiAccent, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'Ask anything — about the article, the people in it, or '
                    'the background you need to understand it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s
                          in arabic ? _suggestionsArabic : _suggestions)
                        _QuestionButton(s, onTap: () => _send(s)),
                    ],
                  ),
                ],
                for (final t in chat.turns)
                  _Bubble(
                    turn: t,
                    // Follow-ups only under the latest, finished answer.
                    onFollowUp: identical(t, lastAnswer) && !chat.busy
                        ? _send
                        : null,
                  ),
                if (chat.preparing || chat.thinking)
                  _Status(
                    chat.preparing
                        ? 'Reading the article and looking up background…'
                        : 'Thinking…',
                  ),
                if (chat.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 18,
                          color: Colors.orangeAccent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(chat.error!)),
                        TextButton(
                          onPressed: () {
                            final q = ref
                                .read(
                                  articleChatProvider(
                                    widget.articleId,
                                  ).notifier,
                                )
                                .retryLast();
                            if (q != null) _send(q);
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 6,
                      textDirection: _inputDirection,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (text) {
                        final dir = textDirectionOf(text);
                        if (dir != _inputDirection) {
                          setState(() => _inputDirection = dir);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: arabic ? 'اسأل سؤالاً…' : 'Ask a question…',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: chat.busy ? null : () => _send(_input.text),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The prepared context, folded: tap to read the background briefing.
class _BriefingCard extends StatelessWidget {
  const _BriefingCard({required this.briefing, required this.onRetry});

  final AsyncValue<ArticleBriefing> briefing;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final b = briefing.value;
    final ready = b != null && b.background.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: aiAccent.withValues(alpha: 0.07),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          enabled: ready,
          leading: briefing.isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  ready ? Icons.travel_explore : Icons.article_outlined,
                  color: aiAccent,
                ),
          title: Text(
            briefing.isLoading
                ? 'Preparing background…'
                : ready
                ? 'Background ready'
                : 'Using the article only',
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            briefing.isLoading
                ? 'Reading the article and searching for context'
                : ready && b.sources.isNotEmpty
                ? 'Researched on the web · tap to read'
                : ready
                ? 'From Gemini\'s own knowledge · tap to read'
                : 'Couldn\'t prepare it: ${b?.error ?? 'unknown error'}',
            style: const TextStyle(fontSize: 12.5, color: Colors.white54),
          ),
          trailing: briefing.isLoading || ready
              ? null
              : TextButton(onPressed: onRetry, child: const Text('Retry')),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            if (ready) ...[SimpleMarkdown(b.background), _Sources(b.sources)],
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(text, style: const TextStyle(color: Colors.white60)),
        ),
      ],
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.turn, this.onFollowUp});

  final ChatTurn turn;

  /// Set on the latest answer: its follow-up questions become chips.
  final ValueChanged<String>? onFollowUp;

  @override
  Widget build(BuildContext context) {
    final user = turn.fromUser;
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * (user ? 0.8 : 0.94),
      ),
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: user
            ? aiAccent.withValues(alpha: 0.22)
            : const Color(0xFF26262C),
        borderRadius: BorderRadius.circular(16),
      ),
      child: user
          ? SelectableText(
              turn.text,
              textDirection: textDirectionOf(turn.text),
              style: const TextStyle(fontSize: 15),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [SimpleMarkdown(turn.text), _Sources(turn.sources)],
            ),
    );
    return Column(
      crossAxisAlignment: user
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        bubble,
        if (onFollowUp != null && turn.followUps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final q in turn.followUps)
                  _QuestionButton(
                    q,
                    icon: Icons.subdirectory_arrow_right,
                    onTap: () => onFollowUp!(q),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Web pages the answer drew on (from Google Search), as small links.
class _Sources extends StatelessWidget {
  const _Sources(this.sources);

  final List<AiSource> sources;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final s in sources.take(6))
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.link, size: 14),
              label: Text(
                s.title,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => launchUrl(
                Uri.parse(s.url),
                mode: LaunchMode.externalApplication,
              ),
            ),
        ],
      ),
    );
  }
}

/// A tappable suggested question. Wraps onto several lines instead of
/// cutting long questions off (chips are single-line).
class _QuestionButton extends StatelessWidget {
  const _QuestionButton(this.text, {required this.onTap, this.icon});

  final String text;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - 40,
      ),
      child: Material(
        color: aiAccent.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: aiAccent.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            // Arabic questions read right-to-left.
            child: AutoDirection(
              text: text,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(icon, size: 16, color: aiAccent),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      text,
                      softWrap: true,
                      style: const TextStyle(fontSize: 14, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
