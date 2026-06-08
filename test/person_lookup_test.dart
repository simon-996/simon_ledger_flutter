import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/models/person.dart';
import 'package:simon_ledger_flutter/core/models/person_lookup.dart';

void main() {
  group('person lookup helpers', () {
    test('indexes people by uuid', () {
      final alice = _person('alice', 'Alice', 'A');
      final bob = _person('bob', 'Bob', 'B');

      final lookup = peopleByUuid([alice, bob]);

      expect(lookup['alice'], same(alice));
      expect(lookup['bob'], same(bob));
    });

    test('indexes synced remote uuid as an alias', () {
      final alice = _person('local-alice', 'Alice', 'A')
        ..syncedRemoteUuid = 'remote-alice';

      final lookup = peopleByUuid([alice]);

      expect(lookup['local-alice'], same(alice));
      expect(lookup['remote-alice'], same(alice));
    });

    test('indexes linked user uuid as an alias', () {
      final self = _person('self', 'Simon', 'S')..linkedUserUuid = 'user-simon';

      final lookup = peopleByUuid([self]);

      expect(lookup['self'], same(self));
      expect(lookup['user-simon'], same(self));
    });

    test('keeps direct uuid mapping before synced alias', () {
      final localAlice = _person('local-alice', 'Local Alice', 'L')
        ..syncedRemoteUuid = 'remote-alice';
      final remoteAlice = _person('remote-alice', 'Remote Alice', 'R');

      final lookup = peopleByUuid([localAlice, remoteAlice]);

      expect(lookup['local-alice'], same(localAlice));
      expect(lookup['remote-alice'], same(remoteAlice));
    });

    test('returns fallback person when uuid is missing', () {
      final fallback = personOrFallback(peopleByUuid([]), 'missing');

      expect(fallback.uuid, 'missing');
      expect(fallback.name, '未知');
      expect(fallback.avatar, '👤');
    });

    test('renders avatar string with fallback markers', () {
      final lookup = peopleByUuid([
        _person('alice', 'Alice', 'A'),
        _person('bob', 'Bob', 'B'),
      ]);

      expect(avatarsForPeople(lookup, ['alice', 'missing', 'bob']), 'A?B');
    });
  });
}

Person _person(String uuid, String name, String avatar) {
  return Person()
    ..uuid = uuid
    ..name = name
    ..avatar = avatar;
}
