// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ledger_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(LedgerNotifier)
final ledgerProvider = LedgerNotifierProvider._();

final class LedgerNotifierProvider
    extends $AsyncNotifierProvider<LedgerNotifier, List<Ledger>> {
  LedgerNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ledgerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ledgerNotifierHash();

  @$internal
  @override
  LedgerNotifier create() => LedgerNotifier();
}

String _$ledgerNotifierHash() => r'c5d8c9941773a02d7dd9ac3cc620fe816f8c355c';

abstract class _$LedgerNotifier extends $AsyncNotifier<List<Ledger>> {
  FutureOr<List<Ledger>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Ledger>>, List<Ledger>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Ledger>>, List<Ledger>>,
              AsyncValue<List<Ledger>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
