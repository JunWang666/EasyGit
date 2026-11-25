import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The credential store shared by hosting accounts, LFS and the proxy password.
///
/// On macOS EasyGit runs without the App Sandbox and is usually ad-hoc signed,
/// so the Data Protection keychain cannot be used: it requires the
/// keychain-access-groups entitlement plus a provisioning profile, and
/// SecItem calls fail with errSecMissingEntitlement (-34018) without them.
/// The classic macOS keychain works with any signature.
const appSecureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);
