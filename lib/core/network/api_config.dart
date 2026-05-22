class ApiConfig {
  const ApiConfig({required this.baseUrl});

  final String baseUrl;

  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:18080',
  );
}
