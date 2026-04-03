import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_service.dart';

/// Provides the global instance of DatabaseService.
/// This acts as our base Dependency Injection for the database layer.
/// Other providers will watch this to perform DB operations.
final databaseProvider = Provider<DatabaseService>((ref) {
  // In the future, this should probably be initialized asynchronously 
  // before the app runs, or we use a FutureProvider for initialization.
  // For now, we return the legacy global instance.
  return dbService;
});
