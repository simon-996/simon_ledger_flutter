import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_service.dart';
import '../network/api_client.dart';
import '../network/token_store.dart';
import '../repositories/auth_repository.dart';
import '../repositories/ledger_repository.dart';
import '../repositories/person_repository.dart';
import '../repositories/transaction_repository.dart';

/// Provides the global instance of DatabaseService.
/// This acts as our base Dependency Injection for the database layer.
/// Other providers will watch this to perform DB operations.
final databaseProvider = Provider<DatabaseService>((ref) {
  // In the future, this should probably be initialized asynchronously
  // before the app runs, or we use a FutureProvider for initialization.
  // For now, we return the legacy global instance.
  return dbService;
});

final tokenStoreProvider = Provider<TokenStore>((ref) {
  return TokenStore();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(tokenStore: ref.watch(tokenStoreProvider));
});

final authTokenProvider = FutureProvider<AuthToken?>((ref) {
  return ref.watch(tokenStoreProvider).read();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return RemoteAuthRepository(
    apiClient: ref.watch(apiClientProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  final token = ref.watch(authTokenProvider).valueOrNull;
  if (token != null && token.isValid) {
    return RemoteLedgerRepository(ref.watch(apiClientProvider));
  }
  return LocalLedgerRepository(ref.watch(databaseProvider));
});

final personRepositoryProvider = Provider<PersonRepository>((ref) {
  final token = ref.watch(authTokenProvider).valueOrNull;
  if (token != null && token.isValid) {
    return RemotePersonRepository(
      apiClient: ref.watch(apiClientProvider),
      ledgerRepository: ref.watch(ledgerRepositoryProvider),
    );
  }
  return LocalPersonRepository(ref.watch(databaseProvider));
});

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final token = ref.watch(authTokenProvider).valueOrNull;
  if (token != null && token.isValid) {
    return RemoteTransactionRepository(ref.watch(apiClientProvider));
  }
  return LocalTransactionRepository(ref.watch(databaseProvider));
});
