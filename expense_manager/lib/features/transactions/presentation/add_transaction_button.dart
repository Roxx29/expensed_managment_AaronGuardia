import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/l10n/l10n.dart';

class AddTransactionButton extends StatelessWidget {
  const AddTransactionButton({super.key});

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
        heroTag: null, // several tabs show this button at once
        onPressed: () => context.push(Routes.newTransaction),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.tr('Add')),
      );
}
