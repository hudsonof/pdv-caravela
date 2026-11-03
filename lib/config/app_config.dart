class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const terminalId = String.fromEnvironment(
    'TERMINAL_ID',
    defaultValue: 'pos-terminal',
  );

  static const supportContact = String.fromEnvironment(
    'SUPPORT_CONTACT',
    defaultValue: '',
  );

  static const appName = 'Caravela PDV';
  static const apiPrefix = '/api/pos/v1';
  static const stoneReturnScheme = 'caravelapdv';

  static bool get isConfigured {
    final uri = Uri.tryParse(apiBaseUrl);
    return uri != null &&
        (uri.scheme == 'https' || uri.host == 'localhost' || uri.host == '10.0.2.2') &&
        uri.host.isNotEmpty;
  }
}
