// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TransactionNotifier)
final transactionProvider = TransactionNotifierFamily._();

final class TransactionNotifierProvider
    extends
        $AsyncNotifierProvider<TransactionNotifier, List<TransactionRecord>> {
  TransactionNotifierProvider._({
    required TransactionNotifierFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'transactionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$transactionNotifierHash();

  @override
  String toString() {
    return r'transactionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TransactionNotifier create() => TransactionNotifier();

  @override
  bool operator ==(Object other) {
    return other is TransactionNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$transactionNotifierHash() =>
    r'b49c75df1b2fab125e223f8974f70cb30972390f';

final class TransactionNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          TransactionNotifier,
          AsyncValue<List<TransactionRecord>>,
          List<TransactionRecord>,
          FutureOr<List<TransactionRecord>>,
          String
        > {
  TransactionNotifierFamily._()
    : super(
        retry: null,
        name: r'transactionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TransactionNotifierProvider call(String ledgerUuid) =>
      TransactionNotifierProvider._(argument: ledgerUuid, from: this);

  @override
  String toString() => r'transactionProvider';
}

abstract class _$TransactionNotifier
    extends $AsyncNotifier<List<TransactionRecord>> {
  late final _$args = ref.$arg as String;
  String get ledgerUuid => _$args;

  FutureOr<List<TransactionRecord>> build(String ledgerUuid);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<TransactionRecord>>,
              List<TransactionRecord>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<TransactionRecord>>,
                List<TransactionRecord>
              >,
              AsyncValue<List<TransactionRecord>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
