// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'person_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PersonNotifier)
final personProvider = PersonNotifierFamily._();

final class PersonNotifierProvider
    extends $AsyncNotifierProvider<PersonNotifier, List<Person>> {
  PersonNotifierProvider._({
    required PersonNotifierFamily super.from,
    required ({bool includeDeleted, String? ledgerUuid}) super.argument,
  }) : super(
         retry: null,
         name: r'personProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$personNotifierHash();

  @override
  String toString() {
    return r'personProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  PersonNotifier create() => PersonNotifier();

  @override
  bool operator ==(Object other) {
    return other is PersonNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$personNotifierHash() => r'237e11293fdb1fc3bcce18610ba0e164e7ae93cb';

final class PersonNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          PersonNotifier,
          AsyncValue<List<Person>>,
          List<Person>,
          FutureOr<List<Person>>,
          ({bool includeDeleted, String? ledgerUuid})
        > {
  PersonNotifierFamily._()
    : super(
        retry: null,
        name: r'personProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  PersonNotifierProvider call({
    bool includeDeleted = false,
    String? ledgerUuid,
  }) => PersonNotifierProvider._(
    argument: (includeDeleted: includeDeleted, ledgerUuid: ledgerUuid),
    from: this,
  );

  @override
  String toString() => r'personProvider';
}

abstract class _$PersonNotifier extends $AsyncNotifier<List<Person>> {
  late final _$args = ref.$arg as ({bool includeDeleted, String? ledgerUuid});
  bool get includeDeleted => _$args.includeDeleted;
  String? get ledgerUuid => _$args.ledgerUuid;

  FutureOr<List<Person>> build({
    bool includeDeleted = false,
    String? ledgerUuid,
  });
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Person>>, List<Person>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Person>>, List<Person>>,
              AsyncValue<List<Person>>,
              Object?,
              Object?
            >;
    element.handleCreate(
      ref,
      () => build(
        includeDeleted: _$args.includeDeleted,
        ledgerUuid: _$args.ledgerUuid,
      ),
    );
  }
}
