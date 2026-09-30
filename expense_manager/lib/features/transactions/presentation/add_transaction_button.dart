import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';

class AddTransactionButton extends StatelessWidget {
  const AddTransactionButton({super.key});

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
        heroTag: null, // several tabs show this button at once
        onPressed: () => context.push(Routes.newTransaction),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      );
}
