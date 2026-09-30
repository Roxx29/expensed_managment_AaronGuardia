import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/utils/validators.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../application/profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ref.watch(profileProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(
              child: EmptyState(icon: Icons.error_outline_rounded, message: 'Could not load your profile.'),
            ),
            data: (profile) => _ProfileForm(profile: profile),
          ),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.name);
  late final _email = TextEditingController(text: widget.profile.email ?? '');
  late String? _country = widget.profile.countryCode;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(profileActionsProvider).save(
            name: _name.text,
            email: _email.text,
            countryCode: _country,
          );
      messenger.showSnackBar(const SnackBar(content: Text('Profile saved')));
    } on Object {
      messenger.showSnackBar(const SnackBar(content: Text('Could not save the profile.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _photoOptions() async {
    final hasPhoto = widget.profile.avatarPath != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final actions = ref.read(profileActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (choice == 'pick') {
        await actions.pickPhoto();
      } else {
        await actions.removePhoto();
      }
    } on Object {
      messenger.showSnackBar(const SnackBar(content: Text('Could not update the photo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = ref.watch(avatarFileProvider).value;
    final currency = ref.watch(currencyProvider);
    final name = widget.profile.name.trim();
    final scheme = Theme.of(context).colorScheme;

    return Form(
      key: _formKey,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.medium),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Semantics(
                    button: true,
                    label: 'Change profile photo',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _photoOptions,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: scheme.primaryContainer,
                            foregroundImage: avatar == null ? null : FileImage(avatar),
                            child: Text(
                              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                  ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: scheme.primary,
                              child: Icon(Icons.photo_camera_rounded, size: 16, color: scheme.onPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _email,
                  maxLength: 120,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    return text.isEmpty || emailPattern.hasMatch(text) ? null : 'Enter a valid email';
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: countries.containsKey(_country) ? _country : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Country'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Not specified')),
                    for (final e in countries.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (c) => setState(() => _country = c),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.payments_outlined),
                  title: Text('${currency.code} — ${currency.displayName}'),
                  subtitle: const Text('Main currency · change it in Settings'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.settings),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your profile is stored only on this device.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
