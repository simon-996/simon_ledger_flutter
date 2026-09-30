import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simon_ledger_flutter/core/database/database_service.dart';
import 'package:simon_ledger_flutter/core/database/local_data_scope.dart';
import 'package:simon_ledger_flutter/core/models/ledger.dart';
import 'package:simon_ledger_flutter/core/models/local_profile.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/person_lookup.dart';
import 'package:simon_ledger_flutter/core/models/transaction_record.dart';
import 'package:simon_ledger_flutter/core/network/api_client.dart';
import 'package:simon_ledger_flutter/core/network/token_store.dart';
import 'package:simon_ledger_flutter/core/preferences/local_profile_store.dart';
import 'package:simon_ledger_flutter/core/repositories/ledger_repository.dart';
import 'package:simon_ledger_flutter/core/repositories/person_repository.dart';
import 'package:simon_ledger_flutter/core/services/sync_identity_resolver.dart';
import 'package:simon_ledger_flutter/core/widgets/app_components.dart';

const _accountScope = LocalDataScope.account('account-a');
const _cloudProfile = LocalProfile(nickname: 'Cloud Simon', avatarIcon: 'star');
const _remoteA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _personA = '11111111111111111111111111111111';
const _personB = '22222222222222222222222222222222';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await const LocalProfileStore(scope: _accountScope).save(_cloudProfile);
  });

  testWidgets(
    'claim converts self and displays it once, preserving a same-name manual person',
    (tester) async {
      final guest = DatabaseService();
      final account = DatabaseService(scope: _accountScope);
      await guest.savePerson(_person('self', 'Local Simon'));
      await guest.savePerson(_person('manual', 'Local Simon'));
      await guest.saveLedger(_ledger('local-a', ['self', 'manual']));
      final api = _IdentityApi();
      final repo = RemoteLedgerRepository(apiClient: api, database: account);
      await repo.claimLedger('local-a');
      await repo.syncPendingWrites(ledgerUuid: 'local-a');
      final uploaded = (await account.getAllLedgers()).single;
      final people = await account.getAllPeople();
      final self = people.singleWhere(
        (p) => p.uuid == uploaded.personUuids.first,
      );
      final manual = people.singleWhere((p) => p.uuid == 'manual');
      expect(self.linkedUserUuid, 'account-a');
      expect(self.name, 'Cloud Simon');
      expect(self.avatar, '⭐');
      expect(manual.name, 'Local Simon');
      expect(manual.linkedUserUuid, isNull);
      expect(api.creates.single['people'], [
        {'name': 'Cloud Simon', 'avatar': '⭐', 'linkedUserUuid': 'account-a'},
        {'name': 'Local Simon', 'avatar': '🙂', 'linkedUserUuid': null},
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppLedgerPeopleChips(
              sharedMembers: uploaded.members,
              localManualPeople: people
                  .where(
                    (p) =>
                        p.linkedUserUuid == null &&
                        uploaded.personUuids.contains(p.uuid),
                  )
                  .toList(),
              peopleById: peopleByUuid(people),
            ),
          ),
        ),
      );
      expect(find.text('Cloud Simon'), findsOneWidget);
      expect(find.text('Local Simon'), findsOneWidget);
    },
  );

  test(
    'claim separates shared people and preserves historical payer and participant references',
    () async {
      final guest = DatabaseService();
      final account = DatabaseService(scope: _accountScope);
      await guest.savePerson(_person('self', 'Local Simon'));
      await guest.savePerson(_person('friend', 'Alice'));
      await guest.saveLedger(_ledger('local-a', ['self', 'friend']));
      await guest.saveLedger(_ledger('local-b', ['self', 'friend']));
      await guest.saveTransaction(
        _transaction('history-a', 'local-a', ['friend'], payer: 'self')
          ..isDeleted = true,
      );
      await guest.saveTransaction(
        _transaction('history-b', 'local-b', ['self'], payer: 'friend'),
      );
      await account.claimLedger('local-a', 'account-a');
      final first = (await account.getAllLedgers()).singleWhere(
        (l) => l.uuid == 'local-a',
      );
      expect(
        first.personUuids.toSet().intersection({'self', 'friend'}),
        isEmpty,
      );
      final firstHistory = (await account.getTransactionsForLedger(
        'local-a',
        includeDeleted: true,
      )).single;
      expect(firstHistory.payerPersonUuid, first.personUuids.first);
      expect(firstHistory.personUuids, [first.personUuids.last]);
      final guestSelf = (await guest.getAllPeople()).singleWhere(
        (p) => p.uuid == 'self',
      );
      expect(guestSelf.localAccountUuid, isNull);
      expect(guestSelf.linkedUserUuid, isNull);
      expect(guestSelf.name, 'Local Simon');
      final ids = SyncIdentityResolver(account);
      await ids.recordPersonMapping(
        localUuid: first.personUuids.first,
        remoteUuid: _personA,
      );
      await account.claimLedger('local-b', 'account-a');
      final second = (await account.getAllLedgers()).singleWhere(
        (l) => l.uuid == 'local-b',
      );
      await ids.recordPersonMapping(
        localUuid: second.personUuids.first,
        remoteUuid: _personB,
      );
      expect(await ids.resolvePersonUuid(first.personUuids.first), _personA);
      expect(await ids.resolvePersonUuid(second.personUuids.first), _personB);
      expect(
        await ids.resolvePersonUuid(firstHistory.payerPersonUuid!),
        _personA,
      );
      expect(
        (await account.getTransactionsForLedger('local-b')).single.personUuids,
        [second.personUuids.first],
      );
    },
  );

  test(
    'failed upload retries the same claimed self without changing remaining guest data',
    () async {
      final guest = DatabaseService();
      final account = DatabaseService(scope: _accountScope);
      await guest.savePerson(_person('self', 'Local Simon'));
      await guest.saveLedger(_ledger('local-a', ['self']));
      await guest.saveLedger(_ledger('local-b', ['self']));
      final api = _IdentityApi()..failNextCreate = true;
      final repo = RemoteLedgerRepository(apiClient: api, database: account);
      await repo.claimLedger('local-a');
      final before = (await account.getAllLedgers())
          .singleWhere((l) => l.uuid == 'local-a')
          .personUuids
          .single;
      await expectLater(
        repo.syncPendingWrites(ledgerUuid: 'local-a'),
        throwsStateError,
      );
      await repo.syncPendingWrites(ledgerUuid: 'local-a');
      final after = (await account.getAllLedgers()).singleWhere(
        (l) => l.uuid == 'local-a',
      );
      expect(after.personUuids.single, before);
      expect(
        (await account.getAllPeople())
            .singleWhere((p) => p.uuid == before)
            .linkedUserUuid,
        'account-a',
      );
      expect((await guest.getAllPeople()).single.linkedUserUuid, isNull);
      expect(api.createKeys, ['local-a', 'local-a']);
    },
  );

  test(
    'explicit self flag survives storage and binds arbitrary UUID without using nickname',
    () async {
      SharedPreferences.setMockInitialValues({
        'local_store.scope_migration.v2': true,
        'local_store.guest.people.v2': jsonEncode([
          {
            'uuid': 'custom-self',
            'name': 'Local Simon',
            'avatar': '🙂',
            'isLocalSelf': true,
          },
          {'uuid': 'manual', 'name': 'Local Simon', 'avatar': '🙂'},
        ]),
      });
      await const LocalProfileStore(scope: _accountScope).save(_cloudProfile);
      final guest = DatabaseService();
      await guest.savePerson((await guest.getAllPeople()).first);
      final prefs = await SharedPreferences.getInstance();
      expect(
        (jsonDecode(prefs.getString('local_store.guest.people.v2')!) as List)
            .first['isLocalSelf'],
        isTrue,
      );
      await guest.saveLedger(_ledger('local-a', ['custom-self', 'manual']));
      final account = DatabaseService(scope: _accountScope);
      await account.claimLedger('local-a', 'account-a');
      final people = await account.getAllPeople();
      expect(
        people.singleWhere((p) => p.uuid == 'custom-self').linkedUserUuid,
        'account-a',
      );
      expect(
        people.singleWhere((p) => p.uuid == 'manual').linkedUserUuid,
        isNull,
      );
    },
  );

  for (final legacyId in ['p1', 'self-123456789', 'guest:self-123456789']) {
    test('legacy system self $legacyId binds when claimed', () async {
      final guest = DatabaseService();
      await guest.savePerson(_person(legacyId, 'Local Simon'));
      await guest.saveLedger(_ledger('local-a', [legacyId]));
      final account = DatabaseService(scope: _accountScope);
      await account.claimLedger('local-a', 'account-a');
      expect((await account.getAllPeople()).single.linkedUserUuid, 'account-a');
    });
  }

  for (final existingLink in [null, 'account-a', 'other-account']) {
    test(
      'repair uploaded self respects remote account association $existingLink',
      () async {
        final account = DatabaseService(scope: _accountScope);
        await account.saveLedger(
          _ledger('local-a', ['self'])
            ..localAccountUuid = 'account-a'
            ..role = 'owner'
            ..syncedRemoteUuid = _remoteA,
        );
        await account.savePerson(
          _person('self', 'Local Simon')
            ..localAccountUuid = 'account-a'
            ..syncedRemoteUuid = _personA,
        );
        final api = _IdentityApi()..existingLink = existingLink;
        final ledgers = RemoteLedgerRepository(
          apiClient: api,
          database: account,
        );
        final people = RemotePersonRepository(
          apiClient: api,
          ledgerRepository: ledgers,
          database: account,
        );
        await people.syncPendingPeople('local-a');
        final saved = (await account.getAllPeople()).single;
        if (existingLink == 'other-account') {
          expect(api.updates, isEmpty);
          expect(saved.linkedUserUuid, isNull);
        } else {
          expect(saved.linkedUserUuid, 'account-a');
          expect(saved.name, 'Cloud Simon');
          expect(saved.pendingSync, isFalse);
          expect(api.updates, hasLength(existingLink == null ? 1 : 0));
          if (api.updates.isNotEmpty) expect(api.updates.single['version'], 3);
        }
      },
    );
  }

  test(
    'repair follows mapped ledger membership after remote refresh and updates both cached aliases',
    () async {
      final account = DatabaseService(scope: _accountScope);
      await account.saveLedger(
        _ledger('local-a', [_personA])
          ..localAccountUuid = 'account-a'
          ..syncedRemoteUuid = _remoteA
          ..role = 'owner',
      );
      await account.savePerson(
        _person('self', 'Local Simon')
          ..localAccountUuid = 'account-a'
          ..syncedRemoteUuid = _personA,
      );
      await account.savePerson(
        _person(_personA, 'Local Simon')..localAccountUuid = 'account-a',
      );
      final api = _IdentityApi();
      final people = RemotePersonRepository(
        apiClient: api,
        ledgerRepository: RemoteLedgerRepository(
          apiClient: api,
          database: account,
        ),
        database: account,
      );
      await people.syncPendingPeople('local-a');
      final cached = await account.getAllPeople();
      expect(cached.map((p) => p.linkedUserUuid), everyElement('account-a'));
      expect(cached.map((p) => p.name), everyElement('Cloud Simon'));
      expect(api.updates, hasLength(1));
    },
  );

  test(
    'repair includes a historical self payer outside the current people selection',
    () async {
      final account = DatabaseService(scope: _accountScope);
      await account.saveLedger(
        _ledger('local-a', [])
          ..localAccountUuid = 'account-a'
          ..syncedRemoteUuid = _remoteA
          ..role = 'owner',
      );
      await account.savePerson(
        _person('self', 'Local Simon')
          ..localAccountUuid = 'account-a'
          ..syncedRemoteUuid = _personA,
      );
      await account.saveTransaction(
        _transaction('history-a', 'local-a', [], payer: 'self')
          ..isDeleted = true,
      );
      final api = _IdentityApi();
      final people = RemotePersonRepository(
        apiClient: api,
        ledgerRepository: RemoteLedgerRepository(
          apiClient: api,
          database: account,
        ),
        database: account,
      );
      await people.syncPendingPeople('local-a');
      expect((await account.getAllPeople()).single.linkedUserUuid, 'account-a');
      expect((await account.getAllLedgers()).single.personUuids, isEmpty);
    },
  );
}

Person _person(String id, String name) => Person()
  ..uuid = id
  ..name = name
  ..avatar = '🙂';
Ledger _ledger(String id, List<String> people) => Ledger()
  ..uuid = id
  ..name = id
  ..baseCurrencyCode = 'CNY'
  ..personUuids = people;
TransactionRecord _transaction(
  String id,
  String ledger,
  List<String> people, {
  String? payer,
}) => TransactionRecord()
  ..uuid = id
  ..ledgerUuid = ledger
  ..personUuids = people
  ..payerPersonUuid = payer
  ..amount = 12
  ..currencyCode = 'CNY'
  ..category = '餐饮'
  ..note = ''
  ..createdAt = DateTime(2026, 9, 30);

class _IdentityApi extends ApiClient {
  _IdentityApi() : super(tokenStore: TokenStore());
  final List<Map<String, dynamic>> creates = [];
  final List<String?> createKeys = [];
  final List<Map<String, dynamic>> updates = [];
  bool failNextCreate = false;
  String? existingLink;

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    if (path != '/api/ledgers/with-people') throw UnimplementedError(path);
    final body = data as Map<String, dynamic>;
    creates.add(body);
    createKeys.add(idempotencyKey);
    if (failNextCreate) {
      failNextCreate = false;
      throw StateError('offline');
    }
    final input = body['people'] as List<dynamic>;
    return fromJson!({
      'ledger': {
        'uuid': _remoteA,
        'name': body['name'],
        'baseCurrencyCode': 'CNY',
        'exchangeRateToCny': 1,
        'role': 'owner',
        'memberCount': 1,
        'version': 1,
        'members': [
          {
            'uuid': 'member-a',
            'userUuid': 'account-a',
            'nickname': 'Cloud Simon',
            'avatar': '⭐',
            'role': 'owner',
            'version': 1,
          },
        ],
      },
      'people': [
        for (var i = 0; i < input.length; i++)
          {
            ...input[i] as Map<String, dynamic>,
            'uuid': i == 0 ? _personA : _personB,
            'version': 1,
          },
      ],
    });
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(Object? json)? fromJson,
  }) async {
    if (path != '/api/ledgers/$_remoteA/people') throw UnimplementedError(path);
    return fromJson!([
      {
        'uuid': _personA,
        'name': existingLink == 'account-a' ? 'Cloud Simon' : 'Local Simon',
        'avatar': existingLink == 'account-a' ? '⭐' : '🙂',
        'linkedUserUuid': existingLink,
        'version': 3,
      },
    ]);
  }

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    String? idempotencyKey,
    T Function(Object? json)? fromJson,
  }) async {
    if (path != '/api/ledgers/$_remoteA/people/$_personA') {
      throw UnimplementedError(path);
    }
    final body = data as Map<String, dynamic>;
    updates.add(body);
    return fromJson!({...body, 'uuid': _personA, 'version': 4});
  }
}
