import 'ledger.dart';
import '../repositories/invite_repository.dart';

class InviteJoinResult {
  const InviteJoinResult({
    required this.invite,
    this.ledger,
    this.member,
    this.person,
  });

  final LedgerInvite invite;
  final InviteJoinLedger? ledger;
  final InviteJoinMember? member;
  final InviteJoinPerson? person;

  bool get isComplete => ledger != null && member != null && person != null;

  bool get isValid {
    final ledgerSnapshot = ledger;
    final memberSnapshot = member;
    final personSnapshot = person;
    if (!isComplete ||
        ledgerSnapshot == null ||
        memberSnapshot == null ||
        personSnapshot == null) {
      return false;
    }
    return ledgerSnapshot.uuid.trim().isNotEmpty &&
        ledgerSnapshot.version > 0 &&
        ledgerSnapshot.memberCount >= 0 &&
        memberSnapshot.uuid.trim().isNotEmpty &&
        memberSnapshot.userUuid.trim().isNotEmpty &&
        memberSnapshot.status == 1 &&
        memberSnapshot.version > 0 &&
        personSnapshot.uuid.trim().isNotEmpty &&
        personSnapshot.ledgerUuid == ledgerSnapshot.uuid &&
        personSnapshot.linkedUserUuid == memberSnapshot.userUuid &&
        personSnapshot.linkedUserUuid.trim().isNotEmpty &&
        personSnapshot.version > 0 &&
        invite.ledgerUuid == ledgerSnapshot.uuid;
  }

  factory InviteJoinResult.fromJson(Object? json) {
    final map = (json as Map<Object?, Object?>).cast<String, dynamic>();
    final inviteJson = map['invite'];
    final invite = LedgerInvite.fromJson(
      inviteJson is Map<Object?, Object?>
          ? inviteJson.cast<String, dynamic>()
          : map,
    );
    return InviteJoinResult(
      invite: invite,
      ledger: _asMap(map['ledger']) == null
          ? null
          : InviteJoinLedger.fromJson(_asMap(map['ledger'])!),
      member: _asMap(map['member']) == null
          ? null
          : InviteJoinMember.fromJson(_asMap(map['member'])!),
      person: _asMap(map['person']) == null
          ? null
          : InviteJoinPerson.fromJson(_asMap(map['person'])!),
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    return value.cast<String, dynamic>();
  }
}

class InviteJoinLedger {
  const InviteJoinLedger({
    required this.uuid,
    required this.name,
    required this.baseCurrencyCode,
    required this.exchangeRateToCny,
    required this.version,
    required this.role,
    required this.memberCount,
    required this.members,
  });

  final String uuid;
  final String name;
  final String baseCurrencyCode;
  final double exchangeRateToCny;
  final int version;
  final String? role;
  final int memberCount;
  final List<LedgerMemberSummary> members;

  factory InviteJoinLedger.fromJson(Map<String, dynamic> map) {
    final members = (map['members'] as List<dynamic>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(
          (value) => LedgerMemberSummary(
            uuid: value['uuid']?.toString() ?? '',
            userUuid: value['userUuid']?.toString(),
            nickname: value['nickname']?.toString(),
            avatar: value['avatar']?.toString(),
            role: value['role']?.toString(),
            version: (value['version'] as num?)?.toInt() ?? 1,
          ),
        )
        .toList();
    return InviteJoinLedger(
      uuid: map['uuid']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      baseCurrencyCode: map['baseCurrencyCode']?.toString() ?? 'CNY',
      exchangeRateToCny: (map['exchangeRateToCny'] as num?)?.toDouble() ?? 1,
      version: (map['version'] as num?)?.toInt() ?? 1,
      role: map['role']?.toString(),
      memberCount: (map['memberCount'] as num?)?.toInt() ?? members.length,
      members: members,
    );
  }
}

class InviteJoinMember {
  const InviteJoinMember({
    required this.uuid,
    required this.userUuid,
    required this.nickname,
    required this.avatar,
    required this.role,
    required this.status,
    required this.version,
  });

  final String uuid;
  final String userUuid;
  final String? nickname;
  final String? avatar;
  final String role;
  final int status;
  final int version;

  factory InviteJoinMember.fromJson(Map<String, dynamic> map) {
    return InviteJoinMember(
      uuid: map['uuid']?.toString() ?? '',
      userUuid: map['userUuid']?.toString() ?? '',
      nickname: map['nickname']?.toString(),
      avatar: map['avatar']?.toString(),
      role: map['role']?.toString() ?? 'viewer',
      status: (map['status'] as num?)?.toInt() ?? 1,
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }
}

class InviteJoinPerson {
  const InviteJoinPerson({
    required this.uuid,
    required this.ledgerUuid,
    required this.linkedUserUuid,
    required this.name,
    required this.avatar,
    required this.version,
  });

  final String uuid;
  final String ledgerUuid;
  final String linkedUserUuid;
  final String name;
  final String? avatar;
  final int version;

  factory InviteJoinPerson.fromJson(Map<String, dynamic> map) {
    return InviteJoinPerson(
      uuid: map['uuid']?.toString() ?? '',
      ledgerUuid: map['ledgerUuid']?.toString() ?? '',
      linkedUserUuid: map['linkedUserUuid']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      avatar: map['avatar']?.toString(),
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }
}
