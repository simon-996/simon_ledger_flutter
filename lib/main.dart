import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/database_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dbService.init();
  runApp(
    const ProviderScope(
      child: SimonLedgerApp(),
    ),
  );
}
