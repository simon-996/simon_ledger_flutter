// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$transactionNotifierHash() =>
    r'560ae912f8b53bbde4714239cd2c7b62c82a89c9';

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

abstract class _$TransactionNotifier
    extends BuildlessAutoDisposeAsyncNotifier<List<TransactionRecord>> {
  late final String ledgerUuid;

  FutureOr<List<TransactionRecord>> build(
    String ledgerUuid,
  );
}

/// See also [TransactionNotifier].
@ProviderFor(TransactionNotifier)
const transactionNotifierProvider = TransactionNotifierFamily();

/// See also [TransactionNotifier].
class TransactionNotifierFamily
    extends Family<AsyncValue<List<TransactionRecord>>> {
  /// See also [TransactionNotifier].
  const TransactionNotifierFamily();

  /// See also [TransactionNotifier].
  TransactionNotifierProvider call(
    String ledgerUuid,
  ) {
    return TransactionNotifierProvider(
      ledgerUuid,
    );
  }

  @override
  TransactionNotifierProvider getProviderOverride(
    covariant TransactionNotifierProvider provider,
  ) {
    return call(
      provider.ledgerUuid,
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
  String? get name => r'transactionNotifierProvider';
}

/// See also [TransactionNotifier].
class TransactionNotifierProvider extends AutoDisposeAsyncNotifierProviderImpl<
    TransactionNotifier, List<TransactionRecord>> {
  /// See also [TransactionNotifier].
  TransactionNotifierProvider(
    String ledgerUuid,
  ) : this._internal(
          () => TransactionNotifier()..ledgerUuid = ledgerUuid,
          from: transactionNotifierProvider,
          name: r'transactionNotifierProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$transactionNotifierHash,
          dependencies: TransactionNotifierFamily._dependencies,
          allTransitiveDependencies:
              TransactionNotifierFamily._allTransitiveDependencies,
          ledgerUuid: ledgerUuid,
        );

  TransactionNotifierProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.ledgerUuid,
  }) : super.internal();

  final String ledgerUuid;

  @override
  FutureOr<List<TransactionRecord>> runNotifierBuild(
    covariant TransactionNotifier notifier,
  ) {
    return notifier.build(
      ledgerUuid,
    );
  }

  @override
  Override overrideWith(TransactionNotifier Function() create) {
    return ProviderOverride(
      origin: this,
      override: TransactionNotifierProvider._internal(
        () => create()..ledgerUuid = ledgerUuid,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        ledgerUuid: ledgerUuid,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<TransactionNotifier,
      List<TransactionRecord>> createElement() {
    return _TransactionNotifierProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is TransactionNotifierProvider &&
        other.ledgerUuid == ledgerUuid;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, ledgerUuid.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin TransactionNotifierRef
    on AutoDisposeAsyncNotifierProviderRef<List<TransactionRecord>> {
  /// The parameter `ledgerUuid` of this provider.
  String get ledgerUuid;
}

class _TransactionNotifierProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<TransactionNotifier,
        List<TransactionRecord>> with TransactionNotifierRef {
  _TransactionNotifierProviderElement(super.provider);

  @override
  String get ledgerUuid => (origin as TransactionNotifierProvider).ledgerUuid;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
