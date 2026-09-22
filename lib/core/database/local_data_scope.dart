final class LocalDataScope {
  const LocalDataScope._(this.accountUuid);

  const LocalDataScope.guest() : this._(null);

  const LocalDataScope.account(String accountUuid) : this._(accountUuid);

  final String? accountUuid;

  bool get isGuest => accountUuid == null;

  bool get isAccount => accountUuid != null;

  String get storageKey => isGuest ? 'guest' : 'account.$accountUuid';

  @override
  bool operator ==(Object other) {
    return other is LocalDataScope && other.accountUuid == accountUuid;
  }

  @override
  int get hashCode => accountUuid.hashCode;
}
