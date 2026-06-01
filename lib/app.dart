import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/screens/home_page.dart';
import 'features/ledgers/presentation/providers/ledger_provider.dart';
import 'features/ledgers/presentation/providers/ledger_stats_provider.dart';
import 'features/people_pool/presentation/providers/person_provider.dart';
import 'features/transactions/presentation/providers/transaction_provider.dart';

class SimonLedgerApp extends ConsumerStatefulWidget {
  const SimonLedgerApp({super.key});

  @override
  ConsumerState<SimonLedgerApp> createState() => _SimonLedgerAppState();
}

class _SimonLedgerAppState extends ConsumerState<SimonLedgerApp>
    with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        _syncPending();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPending());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPending();
    }
  }

  Future<void> _syncPending() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final token = await ref.read(authTokenProvider.future);
      if (token == null || !token.isValid) return;
      final changed = await ref.read(syncCoordinatorProvider).syncAllPending();
      if (!changed || !mounted) return;
      ref.invalidate(ledgerNotifierProvider);
      ref.invalidate(personNotifierProvider);
      ref.invalidate(transactionNotifierProvider);
      ref.invalidate(ledgerStatsProvider);
    } catch (_) {
      // Silent retry: pending items stay local until the next sync trigger.
    } finally {
      _syncing = false;
    }
  }

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
