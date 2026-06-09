import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/repositories/auth_repository.dart';
import '../../../ledgers/presentation/providers/ledger_provider.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';

final currentUserProvider = FutureProvider<AuthUser?>((ref) async {
  final token = await ref.watch(authTokenProvider.future);
  if (token == null || !token.isValid) {
    return null;
  }

  try {
    final user = await ref.watch(authRepositoryProvider).me();
    final profile = await ref.watch(localProfileStoreProvider).read();
    if (profile.pendingSync) {
      await ref.watch(profileSyncServiceProvider).syncPendingProfile();
    } else {
      await ref.watch(profileSyncServiceProvider).applyRemoteProfile(user);
    }
    ref.invalidate(localProfileProvider);
    ref.invalidate(cachedPeopleProvider);
    ref.invalidate(personProvider);
    ref.invalidate(ledgerProvider);
    return user;
  } on ApiException catch (error) {
    if (error.code == 401001 || error.statusCode == 401) {
      await ref.watch(tokenStoreProvider).clear();
    }
    return null;
  } catch (_) {
    return null;
  }
});
