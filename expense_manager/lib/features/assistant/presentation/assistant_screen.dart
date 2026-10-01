import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../domain/assistant/assistant.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/insights/insights.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../dashboard/presentation/insight_text.dart';
import '../application/assistant_providers.dart';

/// Chat with the on-device assistant. Messages live in memory only (privacy):
/// leaving the screen clears them.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _messages = <({String text, bool fromUser})>[];
  List<String>? _suggestions;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Labels and insight texts are resolved up front; [AssistantLocale.tr]
  /// reads [context], so it must only be used while the screen is mounted
  /// (RuleBasedAssistant uses it synchronously).
  AssistantLocale _locale({Map<String, FinanceCategory> categories = const {}, List<Insight> insights = const []}) {
    final labels = {for (final c in categories.values) c.id: c.label(context)};
    final tips = {for (final i in insights) i: insightMessage(context, i, categories)};
    return AssistantLocale(
      translate: (en, args) => context.tr(en, args),
      formatDate: DateFormat.yMMMd(context.lang).format,
      categoryLabel: (c) => labels[c.id] ?? c.name,
      insightText: (i) => tips[i] ?? '',
    );
  }

  Future<void> _send(String raw) async {
    final question = raw.trim();
    if (question.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _messages.add((text: question, fromUser: true));
      _busy = true;
    });

    AssistantReply reply;
    try {
      final data = await ref.read(assistantContextProvider.future);
      if (!mounted) return;
      reply = await ref
          .read(financeAssistantProvider)
          .ask(question, data, _locale(categories: data.categories, insights: data.dashboard.insights));
    } catch (_) {
      if (!mounted) return;
      reply = AssistantReply(context.tr('Could not load your data. Please restart the app.'));
    }
    if (!mounted) return;
    setState(() {
      _messages.add((text: reply.text, fromUser: false));
      _suggestions = reply.suggestions ?? _suggestions;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(assistantContextProvider); // keep the data warm while open
    final scheme = Theme.of(context).colorScheme;
    final suggestions = _suggestions ?? exampleQuestions(_locale());

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Assistant'))),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    reverse: true, // newest at the bottom, auto-scrolls
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.lock_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  context.tr(
                                      'Answers are computed on your device from your own data. Nothing is sent anywhere. This is not financial advice.'),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final m = _messages[_messages.length - 1 - index];
                      return _Bubble(text: m.text, fromUser: m.fromUser);
                    },
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final s in suggestions)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ActionChip(label: Text(s), onPressed: _busy ? null : () => _send(s)),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _send,
                          decoration: InputDecoration(
                            hintText: context.tr('Ask about your money'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: context.tr('Send'),
                        onPressed: _busy ? null : () => _send(_input.text),
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: fromUser ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: fromUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SelectableText(
            text,
            style: TextStyle(color: fromUser ? scheme.onPrimaryContainer : scheme.onSurface),
          ),
        ),
      ),
    );
  }
}
