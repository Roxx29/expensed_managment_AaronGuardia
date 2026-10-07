import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/premium/application/crash_reporting.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installCrashReporting();
  runApp(const ProviderScope(child: ExpenseManagerApp()));
}
