import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../backup/application/cloud_backup.dart';
import '../application/report_providers.dart';

/// "Report a problem": a ticket the admin reads in the panel (name, e-mail,
/// time and the reason). Needs a signed-in account so we can answer.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  String _category = 'error';
  bool _sending = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _categoryLabel(BuildContext context, String c) => switch (c) {
        'error' => context.tr('App error'),
        'backup' => context.tr('Cloud backup'),
        'sync' => context.tr('Sync'),
        'payments' => context.tr('Premium and payments'),
        _ => context.tr('Something else'),
      };

  Future<void> _send() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final sent = context.tr('Report sent. Thank you!');
    final failed = context.tr('Could not send the report. Check your connection and that your e-mail is verified.');
    try {
      await ref.read(reportActionsProvider).send(category: _category, reason: _reason.text);
      if (!mounted) return;
      router.pop();
      messenger.showSnackBar(SnackBar(content: Text(sent)));
    } on Object {
      // Details are not shown: they could contain user data.
      if (mounted) setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(reportEmailProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Report a problem'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.medium),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: email == null ? _signedOut(context) : _form(context, email),
          ),
        ),
      ),
    );
  }

  Widget _signedOut(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('Sign in so we can answer you by e-mail.')),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: cloudAvailable ? () => context.push(Routes.welcome) : null,
            icon: const Icon(Icons.login_rounded),
            label: Text(context.tr('Sign in')),
          ),
        ],
      );

  Widget _form(BuildContext context, String email) => Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('We will answer to {email}.', {'email': email})),
            const SizedBox(height: 16),
            Text(context.tr('What is it about?'), style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in reportCategories)
                  ChoiceChip(
                    label: Text(_categoryLabel(context, c)),
                    selected: _category == c,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reason,
              minLines: 4,
              maxLines: 8,
              maxLength: reportMaxLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.tr('What happened?'),
                helperText: context.tr('Do not write passwords or your passphrase.'),
              ),
              validator: (v) => (v ?? '').trim().length < reportMinLength
                  ? context.tr('Use at least {count} characters.', {'count': reportMinLength})
                  : null,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              label: Text(context.tr('Send report')),
            ),
          ],
        ),
      );
}
