import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_service.dart';
import '../models/local_profile.dart';
import '../network/api_client.dart';
import '../network/token_store.dart';
import '../preferences/local_profile_store.dart';
import '../repositories/auth_repository.dart';
import '../repositories/invite_repository.dart';
import '../repositories/ledger_repository.dart';
import '../repositories/person_repository.dart';
import '../repositories/transaction_repository.dart';
import '../services/cloud_import_service.dart';
import '../services/profile_sync_service.dart';
import '../services/sync_identity_resolver.dart';

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

final localProfileStoreProvider = Provider<LocalProfileStore>((ref) {
  return const LocalProfileStore();
});

final localProfileProvider = FutureProvider<LocalProfile>((ref) {
  return ref.watch(localProfileStoreProvider).read();
});

final syncIdentityResolverProvider = Provider<SyncIdentityResolver>((ref) {
  return SyncIdentityResolver(ref.watch(databaseProvider));
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
    return RemoteLedgerRepository(
      apiClient: ref.watch(apiClientProvider),
      database: ref.watch(databaseProvider),
    );
  }
  return LocalLedgerRepository(ref.watch(databaseProvider));
});

final inviteRepositoryProvider = Provider<InviteRepository>((ref) {
  return InviteRepository(ref.watch(apiClientProvider));
});

final personRepositoryProvider = Provider<PersonRepository>((ref) {
  final token = ref.watch(authTokenProvider).valueOrNull;
  if (token != null && token.isValid) {
    return RemotePersonRepository(
      apiClient: ref.watch(apiClientProvider),
      ledgerRepository: ref.watch(ledgerRepositoryProvider),
      database: ref.watch(databaseProvider),
    );
  }
  return LocalPersonRepository(ref.watch(databaseProvider));
});

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final token = ref.watch(authTokenProvider).valueOrNull;
  if (token != null && token.isValid) {
    return RemoteTransactionRepository(
      apiClient: ref.watch(apiClientProvider),
      database: ref.watch(databaseProvider),
    );
  }
  return LocalTransactionRepository(ref.watch(databaseProvider));
});

final cloudImportServiceProvider = Provider<CloudImportService>((ref) {
  return CloudImportService(
    database: ref.watch(databaseProvider),
    apiClient: ref.watch(apiClientProvider),
  );
});

final profileSyncServiceProvider = Provider<ProfileSyncService>((ref) {
  return ProfileSyncService(
    localProfileStore: ref.watch(localProfileStoreProvider),
    tokenStore: ref.watch(tokenStoreProvider),
    authRepository: ref.watch(authRepositoryProvider),
    database: ref.watch(databaseProvider),
  );
});
