import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/simple_markdown.dart';
import '../providers/article_ai_providers.dart';
import '../providers/rss_providers.dart';
import '../widgets/article_ai.dart';

/// Ask Gemini about one article.
class ArticleChatScreen extends ConsumerStatefulWidget {
  const ArticleChatScreen({super.key, required this.articleId});

  final String articleId;

  @override
  ConsumerState<ArticleChatScreen> createState() => _ArticleChatScreenState();
}

class _ArticleChatScreenState extends ConsumerState<ArticleChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const _suggestions = [
    'Explain it simply',
    'What are the key facts?',
    'What\'s the background?',
    'Why does this matter?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    _input.clear();
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
    ref.listen(articleChatProvider(widget.articleId), (_, _) => _scrollToEnd());

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
                style: const TextStyle(fontSize: 12.5, color: Colors.white60),
              ),
          ],
        ),
        actions: [
          if (chat.messages.isNotEmpty)
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
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              children: [
                if (chat.messages.isEmpty) ...[
                  const SizedBox(height: 24),
                  const Icon(Icons.auto_awesome, color: aiAccent, size: 36),
                  const SizedBox(height: 10),
                  const Text(
                    'Ask anything about the article.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in _suggestions)
                        ActionChip(label: Text(s), onPressed: () => _send(s)),
                    ],
                  ),
                ],
                for (final m in chat.messages) _Bubble(message: m),
                if (chat.thinking)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Thinking…',
                          style: TextStyle(color: Colors.white60),
                        ),
                      ],
                    ),
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
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: const InputDecoration(
                        hintText: 'Ask a question…',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: chat.thinking ? null : () => _send(_input.text),
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ({bool fromUser, String text}) message;

  @override
  Widget build(BuildContext context) {
    final user = message.fromUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * (user ? 0.8 : 0.92),
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
            ? SelectableText(message.text, style: const TextStyle(fontSize: 15))
            : SimpleMarkdown(message.text),
      ),
    );
  }
}
