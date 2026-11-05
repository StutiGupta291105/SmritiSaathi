/// Address of the Smriti Sathi API, set at build time:
///   flutter build apk --dart-define=API_BASE_URL=https://api.example.com
/// Empty means offline test mode: fixed OTP, nothing leaves the phone.
const String kApiBaseUrl = String.fromEnvironment('API_BASE_URL');

bool get kOnlineConfigured => kApiBaseUrl.isNotEmpty;
