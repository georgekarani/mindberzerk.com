/// Every preference key in the app. Nothing writes a raw string literal to
/// prefs: a typo in a key is silent data loss that surfaces to the user as
/// "my settings reset themselves".
class GPrefsKeys {
  const GPrefsKeys._();

  static const String theme = 'theme';
  static const String shellTab = 'shell_tab';
  static const String onboardingComplete = 'onboarding_complete';

  /// The Play build last offered in the update sheet, so it shows once.
  static const String updateOffered = 'update_offered';

  /// The last comparison scan, in full.
  ///
  /// Findings rather than a setting, and the only entry here that is expensive
  /// to recreate: a scan decodes every photo on the phone. It is written once
  /// per scan and once per removal, and read once per launch.
  static const String compareScan = 'compare_scan';
}
