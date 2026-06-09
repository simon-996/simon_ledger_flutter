import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/providers.dart';
import 'core/services/invite_link_service.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_components.dart';
import 'features/home/presentation/screens/home_page.dart';
import 'features/ledgers/presentation/providers/ledger_provider.dart';
import 'features/ledgers/presentation/providers/ledger_stats_provider.dart';
import 'features/ledgers/presentation/widgets/ledger_invite_widgets.dart';
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
  StreamSubscription<Uri>? _linkSubscription;
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _syncing = false;
  bool _checkingClipboard = false;
  String? _lastOpenedInviteCode;
  String? _lastPromptedClipboardCode;

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
    if (!kIsWeb) {
      _linkSubscription = AppLinks().uriLinkStream.listen(
        _handleInviteUri,
        onError: (_) {},
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPending();
      _checkClipboardInvite();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPending();
      _checkClipboardInvite();
    }
  }

  void _handleInviteUri(Uri uri) {
    final code = InviteLinks.codeFromUri(uri);
    if (code != null) {
      _openInvite(code);
    }
  }

  void _openInvite(String code) {
    final normalizedCode = InviteLinks.tryNormalizeCode(code);
    if (normalizedCode == null || normalizedCode == _lastOpenedInviteCode) {
      return;
    }
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openInvite(normalizedCode),
      );
      return;
    }
    _lastOpenedInviteCode = normalizedCode;
    navigator.pushNamed('/invite/$normalizedCode').whenComplete(() {
      if (_lastOpenedInviteCode == normalizedCode) {
        _lastOpenedInviteCode = null;
      }
    });
  }

  Future<void> _checkClipboardInvite() async {
    if (kIsWeb || _checkingClipboard) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    _checkingClipboard = true;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final code = InviteLinks.codeFromText(data?.text ?? '');
      if (code == null ||
          code == _lastPromptedClipboardCode ||
          InviteClipboardMemory.consumeIgnored(code)) {
        return;
      }
      _lastPromptedClipboardCode = code;
      final context = _navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      AppNotice.info(
        context,
        '检测到账本邀请',
        actionLabel: '查看',
        onAction: () => _openInvite(code),
      );
    } catch (_) {
      // Clipboard access can be denied by the operating system.
    } finally {
      _checkingClipboard = false;
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
      ref.invalidate(ledgerProvider);
      ref.invalidate(personProvider);
      ref.invalidate(transactionProvider);
      ref.invalidate(ledgerStatsProvider);
      ref.invalidate(syncOverviewProvider);
    } catch (_) {
      // Silent retry: pending items stay local until the next sync trigger.
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Simon Ledger',
      theme: AppTheme.lightTheme,
      routes: {
        '/': (context) => const HomePage(),
        '/account': (context) => const HomePage(initialIndex: 3),
      },
      onGenerateRoute: (settings) {
        final code = InviteLinks.codeFromRoute(settings.name);
        if (code == null) return null;
        return MaterialPageRoute<bool>(
          settings: settings,
          builder: (context) => LedgerInviteJoinPage(code: code),
        );
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
