import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/services/sync_identity_resolver.dart';

void main() {
  group('SyncIdentityResolver', () {
    late DatabaseService database;
    late SyncIdentityResolver resolver;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      database = DatabaseService();
      resolver = SyncIdentityResolver(database);
    });

    test('records and resolves ledger remote uuid', () async {
      await database.saveLedger(
        Ledger()
          ..uuid = 'local-ledger'
          ..name = '旅行'
          ..baseCurrencyCode = 'CNY',
      );

      await resolver.recordLedgerMapping(
        localUuid: 'local-ledger',
        remoteUuid: 'remote-ledger',
      );

      expect(await resolver.resolveLedgerUuid('local-ledger'), 'remote-ledger');
      expect(
        await resolver.resolveLedgerUuid('remote-ledger'),
        'remote-ledger',
      );
    });

    test('persists and resolves person remote uuid', () async {
      await database.savePerson(
        Person()
          ..uuid = 'local-person'
          ..name = '本人',
      );

      await resolver.recordPersonMapping(
        localUuid: 'local-person',
        remoteUuid: 'remote-person',
      );

      final reloadedResolver = SyncIdentityResolver(DatabaseService());
      expect(
        await reloadedResolver.resolvePersonUuid('local-person'),
        'remote-person',
      );
      expect(
        await reloadedResolver.resolvePersonUuids([
          'local-person',
          'unknown-person',
        ]),
        ['remote-person', 'unknown-person'],
      );
    });
  });
}
