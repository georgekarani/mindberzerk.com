/// Contacts in search, on every distro. PHASE 9.
///
/// ─── OFF UNTIL THE PERSON TURNS IT ON ───────────────────────────────────────
///
/// The switch is `GlobalPrefs.contactsSearch`, null meaning off. Turning it on
/// asks for READ_CONTACTS; until the switch is on AND the permission is held,
/// [contactHitsProvider] answers empty without calling native, so a phone that
/// never opted in never touches the contacts provider.
///
/// Nothing is cached here either. A query reads a few names and numbers for
/// the line being typed and they are dropped with it.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _channel = MethodChannel('g_launcher/contacts');

/// One contact matching a search.
class ContactHit {
  const ContactHit({required this.name, required this.uri, this.phone});

  final String name;

  /// The contact's primary number, or null when it has none.
  final String? phone;

  /// A lookup uri, which survives the contact being merged or re-synced.
  final String uri;
}

/// Whether READ_CONTACTS is held. Re-read with `ref.invalidate` after the
/// permission dialog closes and on resume, since it can change in Settings.
final contactsGrantedProvider = FutureProvider<bool>((ref) async {
  try {
    return await _channel.invokeMethod<bool>('granted') ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
});

/// Open the system permission dialog. Returns false when it could not be
/// shown; the answer itself arrives as a change in [contactsGrantedProvider].
Future<bool> requestContactsAccess() async {
  try {
    return await _channel.invokeMethod<bool>('request') ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Contacts matching [query], best first. Empty when nothing matches, when the
/// permission is missing, or when the channel is not on this build.
Future<List<ContactHit>> searchContacts(String query, {int limit = 3}) async {
  if (query.trim().length < 2) return const [];
  try {
    final raw = await _channel.invokeListMethod<Object?>(
      'search',
      {'query': query.trim(), 'limit': limit},
    );
    return [
      for (final e in raw ?? const <Object?>[])
        if (e is Map && e['name'] is String && e['uri'] is String)
          ContactHit(
            name: e['name'] as String,
            uri: e['uri'] as String,
            phone: e['phone'] as String?,
          ),
    ];
  } on PlatformException {
    return const [];
  } on MissingPluginException {
    return const [];
  }
}

/// Open the contact card in the phone's contacts app.
Future<bool> openContact(String uri) async {
  try {
    return await _channel.invokeMethod<bool>('open', {'uri': uri}) ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
