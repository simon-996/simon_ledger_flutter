import 'package:flutter/material.dart';
import 'features/home/presentation/screens/home_page.dart';
import 'core/theme/app_theme.dart';

class SimonLedgerApp extends StatelessWidget {
  const SimonLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simon Ledger',
      theme: AppTheme.lightTheme,
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
