import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../i18n/i18n.dart';
import 'gemini_client.dart';

/// Opens [GeminiKeyScreen]; true when a working key is set afterwards.
Future<bool> openGeminiKeySetup(BuildContext context) async {
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const GeminiKeyScreen()));
  if (!context.mounted) return false;
  return ProviderScope.containerOf(
    context,
  ).read(geminiClientProvider).isConfigured;
}

/// Step by step: get a free Gemini API key in Google AI Studio, paste it,
/// and test it before it's saved.
class GeminiKeyScreen extends ConsumerStatefulWidget {
  const GeminiKeyScreen({super.key});

  static final studioUrl = Uri.parse('https://aistudio.google.com/apikey');

  @override
  ConsumerState<GeminiKeyScreen> createState() => _GeminiKeyScreenState();
}

class _GeminiKeyScreenState extends ConsumerState<GeminiKeyScreen> {
  final _controller = TextEditingController();
  var _testing = false;
  String? _error;
  var _saved = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() {
        _controller.text = text;
        _error = null;
      });
    }
  }

  /// One tiny request with the new key; saved only if Gemini answers.
  Future<void> _testAndSave() async {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _testing = true;
      _error = null;
    });
    final client = http.Client();
    try {
      await GeminiClient(client, key).generate(
        messages: const [(fromUser: true, text: 'Reply with: OK')],
        temperature: 0,
      );
      await ref.read(geminiApiKeyProvider.notifier).set(key);
      if (mounted) setState(() => _saved = true);
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configured = ref.watch(geminiClientProvider).isConfigured;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.5,
    );

    Widget step(int n, String text, [Widget? action]) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              '$n',
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(text, style: const TextStyle(height: 1.45)),
                ),
                ?action,
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr('AI features (Gemini)'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            tr(
              'Article summaries, the article chat and lesson explanations use Google Gemini. It needs a free API key from your Google account (about 2 minutes).',
            ),
            style: muted,
          ),
          const SizedBox(height: 20),
          if (configured && !_saved)
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text(tr('A key is set')),
                subtitle: Text(
                  tr(
                    'AI features are ready. Paste a new key below to replace it.',
                  ),
                ),
              ),
            ),
          if (_saved)
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text(tr('Key saved and working')),
                trailing: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('Done')),
                ),
              ),
            ),
          const SizedBox(height: 12),
          step(
            1,
            tr('Open Google AI Studio and sign in with your Google account.'),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(
                  GeminiKeyScreen.studioUrl,
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(tr('Open AI Studio')),
              ),
            ),
          ),
          step(2, tr('Accept the terms if asked, then tap "Create API key".')),
          step(
            3,
            tr(
              'Copy the key (it starts with "AIza"), come back here and paste it.',
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: tr('API key'),
              errorText: _error,
              errorMaxLines: 4,
              suffixIcon: IconButton(
                tooltip: tr('Paste'),
                onPressed: _paste,
                icon: const Icon(Icons.content_paste),
              ),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _testing || _controller.text.trim().isEmpty
                ? null
                : _testAndSave,
            icon: _testing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_testing ? tr('Testing…') : tr('Test & save')),
          ),
          const SizedBox(height: 20),
          Text(
            tr(
              'The key stays on this phone and in your own Drive backup. The free plan has a daily limit; MyKit uses very little of it.',
            ),
            style: muted,
          ),
          if (configured) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () async {
                  await ref.read(geminiApiKeyProvider.notifier).set(null);
                  setState(() => _saved = false);
                },
                icon: const Icon(Icons.delete_outline),
                label: Text(tr('Remove the saved key')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
