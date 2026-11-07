class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://novo-caravela.vercel.app',
  );

  static const supportContact = String.fromEnvironment(
    'SUPPORT_CONTACT',
    defaultValue: '',
  );

  static const appName = 'Caravela PDV';
  static const stoneReturnScheme = 'caravelapdv';

  static bool get isConfigured {
    final uri = Uri.tryParse(apiBaseUrl);
    return uri != null &&
        (uri.scheme == 'https' || uri.host == 'localhost' || uri.host == '10.0.2.2') &&
        uri.host.isNotEmpty;
  }
}
