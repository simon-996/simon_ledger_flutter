class ApiConfig {
  const ApiConfig({required this.baseUrl});

  final String baseUrl;

  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://ledger-api.simon996.com',
  );
}
