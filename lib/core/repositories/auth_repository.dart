import '../network/api_client.dart';
import '../network/token_store.dart';

class AuthUser {
  const AuthUser({
    required this.uuid,
    required this.nickname,
    this.email,
    this.phone,
    this.avatar,
    this.status,
  });

  final String uuid;
  final String nickname;
  final String? email;
  final String? phone;
  final String? avatar;
  final int? status;

  factory AuthUser.fromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return AuthUser(
      uuid: map['uuid'].toString(),
      nickname: map['nickname'].toString(),
      email: map['email']?.toString(),
      phone: map['phone']?.toString(),
      avatar: map['avatar']?.toString(),
      status: (map['status'] as num?)?.toInt(),
    );
  }
}

class AuthLoginResult {
  const AuthLoginResult({required this.token, required this.user});

  final AuthToken token;
  final AuthUser user;

  factory AuthLoginResult.fromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return AuthLoginResult(
      token: AuthToken(
        name: map['tokenName'].toString(),
        value: map['tokenValue'].toString(),
      ),
      user: AuthUser.fromJson(map['user']),
    );
  }
}

abstract class AuthRepository {
  Future<AuthUser> register({
    String? email,
    String? phone,
    required String password,
    required String nickname,
    String? avatar,
  });

  Future<AuthLoginResult> login({
    required String account,
    required String password,
  });

  Future<void> logout();

  Future<AuthUser> me();

  Future<AuthUser> updateProfile({required String nickname, String? avatar});
}

class RemoteAuthRepository implements AuthRepository {
  const RemoteAuthRepository({
    required ApiClient apiClient,
    required TokenStore tokenStore,
  }) : _apiClient = apiClient,
       _tokenStore = tokenStore;

  final ApiClient _apiClient;
  final TokenStore _tokenStore;

  @override
  Future<AuthUser> register({
    String? email,
    String? phone,
    required String password,
    required String nickname,
    String? avatar,
  }) {
    return _apiClient.post<AuthUser>(
      '/api/auth/register',
      data: {
        'email': email,
        'phone': phone,
        'password': password,
        'nickname': nickname,
        'avatar': avatar,
      },
      fromJson: AuthUser.fromJson,
    );
  }

  @override
  Future<AuthLoginResult> login({
    required String account,
    required String password,
  }) async {
    final result = await _apiClient.post<AuthLoginResult>(
      '/api/auth/login',
      data: {'account': account, 'password': password},
      fromJson: AuthLoginResult.fromJson,
    );
    await _tokenStore.save(result.token);
    return result;
  }

  @override
  Future<void> logout() async {
    await _apiClient.post<Object?>(
      '/api/auth/logout',
      fromJson: (json) => json,
    );
    await _tokenStore.clear();
  }

  @override
  Future<AuthUser> me() {
    return _apiClient.get<AuthUser>(
      '/api/auth/me',
      fromJson: AuthUser.fromJson,
    );
  }

  @override
  Future<AuthUser> updateProfile({required String nickname, String? avatar}) {
    return _apiClient.put<AuthUser>(
      '/api/auth/me',
      data: {'nickname': nickname, 'avatar': avatar},
      fromJson: AuthUser.fromJson,
    );
  }
}
