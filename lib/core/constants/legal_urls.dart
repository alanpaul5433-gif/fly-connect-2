/// Public legal pages — the single source of truth for these URLs.
///
/// Hosted on the marketing site (flyconnect.co), NOT the deep-link domain
/// (flyconnect.app). Both app stores fetch the privacy URL during review, and
/// signup links to both for UGC consent. Keep them here so the signup gate and
/// the settings tiles can never drift apart (which is exactly what happened with
/// the old flyconnect.app/{privacy,terms} links).
class LegalUrls {
  LegalUrls._();

  static const String privacyPolicy = 'https://flyconnect.co/privacy-policy/';
  static const String termsOfService = 'https://flyconnect.co/terms-of-service/';
}
