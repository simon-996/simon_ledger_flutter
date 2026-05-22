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
