import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/routes.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/money/currency.dart';
import '../../../domain/import/receipt_parser.dart';
import '../../../shared/providers/providers.dart';
import '../../transactions/presentation/transaction_form_screen.dart';

/// Lets the user photograph or pick a receipt and reads it on-device.
/// Returns null if cancelled or nothing useful was found.
Future<TransactionDraft?> scanReceipt(BuildContext context, Currency currency, {bool preferMonthFirst = false}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded),
            title: Text(context.tr('Take a photo')),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: Text(context.tr('Choose from gallery')),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  final messenger = ScaffoldMessenger.of(context);
  final nothingText = context.tr('No total, date or store found. Try a clearer photo.');
  final failedText = context.tr('Could not read the receipt on this device.');

  final XFile? image;
  try {
    image = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 85);
  } on PlatformException {
    messenger.showSnackBar(SnackBar(content: Text(failedText)));
    return null;
  }
  if (image == null) return null;

  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final List<String> lines;
  try {
    final recognized = await recognizer.processImage(InputImage.fromFilePath(image.path));
    lines = [for (final block in recognized.blocks) for (final line in block.lines) line.text];
  } on Object {
    // Any ML Kit / platform failure: tell the user, never crash the form.
    messenger.showSnackBar(SnackBar(content: Text(failedText)));
    return null;
  } finally {
    await recognizer.close();
    // The camera photo is our own temp copy; gallery files are never touched.
    if (source == ImageSource.camera) {
      try {
        await File(image.path).delete();
      } on FileSystemException {
        // Already gone; the OS clears the cache anyway.
      }
    }
  }

  final data = parseReceipt(lines, currency, now: DateTime.now(), preferMonthFirst: preferMonthFirst);
  if (data.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(nothingText)));
    return null;
  }
  return TransactionDraft(amount: data.total, description: data.merchant, occurredAt: data.date);
}

/// App-bar action for the new-transaction form: scans a receipt and reopens
/// the form prefilled.
class ScanReceiptButton extends ConsumerWidget {
  const ScanReceiptButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
        tooltip: context.tr('Scan receipt'),
        icon: const Icon(Icons.document_scanner_rounded),
        onPressed: () async {
          final draft = await scanReceipt(
            context,
            ref.read(currencyProvider),
            preferMonthFirst: ref.read(profileProvider).value?.countryCode == 'US',
          );
          if (draft == null || !context.mounted) return;
          context.pushReplacement(Routes.newTransaction, extra: draft);
        },
      );
}
