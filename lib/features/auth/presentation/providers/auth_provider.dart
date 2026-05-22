import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/repositories/auth_repository.dart';

final currentUserProvider = FutureProvider<AuthUser?>((ref) async {
  final token = await ref.watch(authTokenProvider.future);
  if (token == null || !token.isValid) {
    return null;
  }

  try {
    return await ref.watch(authRepositoryProvider).me();
  } catch (_) {
    await ref.watch(tokenStoreProvider).clear();
    return null;
  }
});
