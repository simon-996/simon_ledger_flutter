// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ledger_stats_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(LedgerStats)
final ledgerStatsProvider = LedgerStatsProvider._();

final class LedgerStatsProvider
    extends
        $AsyncNotifierProvider<LedgerStats, Map<String, Map<String, double>>> {
  LedgerStatsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ledgerStatsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ledgerStatsHash();

  @$internal
  @override
  LedgerStats create() => LedgerStats();
}

String _$ledgerStatsHash() => r'ae43f9ec2796df55c4e41d71f88d351f09677610';

abstract class _$LedgerStats
    extends $AsyncNotifier<Map<String, Map<String, double>>> {
  FutureOr<Map<String, Map<String, double>>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<Map<String, Map<String, double>>>,
              Map<String, Map<String, double>>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<Map<String, Map<String, double>>>,
                Map<String, Map<String, double>>
              >,
              AsyncValue<Map<String, Map<String, double>>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
