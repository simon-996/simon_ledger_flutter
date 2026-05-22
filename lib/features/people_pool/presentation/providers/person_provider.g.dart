// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'person_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$personNotifierHash() => r'e268b9f3350bbc029998c66b5a2cfce0a6ce3faf';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$PersonNotifier
    extends BuildlessAutoDisposeAsyncNotifier<List<Person>> {
  late final bool includeDeleted;
  late final String? ledgerUuid;

  FutureOr<List<Person>> build({
    bool includeDeleted = false,
    String? ledgerUuid,
  });
}

/// See also [PersonNotifier].
@ProviderFor(PersonNotifier)
const personNotifierProvider = PersonNotifierFamily();

/// See also [PersonNotifier].
class PersonNotifierFamily extends Family<AsyncValue<List<Person>>> {
  /// See also [PersonNotifier].
  const PersonNotifierFamily();

  /// See also [PersonNotifier].
  PersonNotifierProvider call({
    bool includeDeleted = false,
    String? ledgerUuid,
  }) {
    return PersonNotifierProvider(
      includeDeleted: includeDeleted,
      ledgerUuid: ledgerUuid,
    );
  }

  @override
  PersonNotifierProvider getProviderOverride(
    covariant PersonNotifierProvider provider,
  ) {
    return call(
      includeDeleted: provider.includeDeleted,
      ledgerUuid: provider.ledgerUuid,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'personNotifierProvider';
}

/// See also [PersonNotifier].
class PersonNotifierProvider
    extends AutoDisposeAsyncNotifierProviderImpl<PersonNotifier, List<Person>> {
  /// See also [PersonNotifier].
  PersonNotifierProvider({bool includeDeleted = false, String? ledgerUuid})
    : this._internal(
        () => PersonNotifier()
          ..includeDeleted = includeDeleted
          ..ledgerUuid = ledgerUuid,
        from: personNotifierProvider,
        name: r'personNotifierProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$personNotifierHash,
        dependencies: PersonNotifierFamily._dependencies,
        allTransitiveDependencies:
            PersonNotifierFamily._allTransitiveDependencies,
        includeDeleted: includeDeleted,
        ledgerUuid: ledgerUuid,
      );

  PersonNotifierProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.includeDeleted,
    required this.ledgerUuid,
  }) : super.internal();

  final bool includeDeleted;
  final String? ledgerUuid;

  @override
  FutureOr<List<Person>> runNotifierBuild(covariant PersonNotifier notifier) {
    return notifier.build(
      includeDeleted: includeDeleted,
      ledgerUuid: ledgerUuid,
    );
  }

  @override
  Override overrideWith(PersonNotifier Function() create) {
    return ProviderOverride(
      origin: this,
      override: PersonNotifierProvider._internal(
        () => create()
          ..includeDeleted = includeDeleted
          ..ledgerUuid = ledgerUuid,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        includeDeleted: includeDeleted,
        ledgerUuid: ledgerUuid,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<PersonNotifier, List<Person>>
  createElement() {
    return _PersonNotifierProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PersonNotifierProvider &&
        other.includeDeleted == includeDeleted &&
        other.ledgerUuid == ledgerUuid;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, includeDeleted.hashCode);
    hash = _SystemHash.combine(hash, ledgerUuid.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin PersonNotifierRef on AutoDisposeAsyncNotifierProviderRef<List<Person>> {
  /// The parameter `includeDeleted` of this provider.
  bool get includeDeleted;

  /// The parameter `ledgerUuid` of this provider.
  String? get ledgerUuid;
}

class _PersonNotifierProviderElement
    extends
        AutoDisposeAsyncNotifierProviderElement<PersonNotifier, List<Person>>
    with PersonNotifierRef {
  _PersonNotifierProviderElement(super.provider);

  @override
  bool get includeDeleted => (origin as PersonNotifierProvider).includeDeleted;
  @override
  String? get ledgerUuid => (origin as PersonNotifierProvider).ledgerUuid;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
