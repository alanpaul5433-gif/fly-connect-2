import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/real_providers.dart';

/// Centralized "start a chat with this user" helper.
///
/// Three call-sites in the app (profile, nearby, match) used to inline
/// the same pattern: call ChatProvider.getOrCreateDm, then push the
/// conversation route with the other user's name + photo as query params.
///
/// Bugs that this consolidates:
///   1. Some call-sites URL-encoded the name, others didn't — emojis
///      in display names broke the conversation header.
///   2. Some showed a SnackBar on failure, others swallowed it.
///   3. Mock-mode chatId of empty string was inconsistently handled.
///
/// Always use this instead of calling getOrCreateDm directly.
class OpenChat {
  OpenChat._();

  /// Opens (or creates) a DM with [otherUid] and navigates to the
  /// conversation. Pulls the other user's name + photo from the provided
  /// args (caller already has them, no extra Firestore round-trip).
  ///
  /// Returns true on success, false on failure (a SnackBar has already
  /// been shown by this point so the caller doesn't need to).
  static Future<bool> withUser(
    BuildContext context, {
    required String otherUid,
    required String otherName,
    String? otherPhotoUrl,
  }) async {
    final chatProvider = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final chatId = await chatProvider.getOrCreateDm(otherUid);
      if (chatId.isEmpty) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Sign in to start a chat.'),
          backgroundColor: Colors.orange,
        ));
        return false;
      }
      final params = <String, String>{
        'name': otherName.trim().isEmpty ? 'Chat' : otherName,
        // H11: without this the conversation screen falls back to
        // `otherUid ?? chatId`, so Block/Report from a match, profile or
        // nearby chat wrote users/{me}/blocked/{chatDocId} — a document id
        // that is not a user. The block succeeded, the snackbar appeared, and
        // nobody was blocked.
        'otherUid': otherUid,
        if (otherPhotoUrl != null && otherPhotoUrl.isNotEmpty)
          'photo': otherPhotoUrl,
      };
      // URL-encode every param so emojis / unicode survive the route.
      final qs = params.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      router.push('/conversation/$chatId?$qs');
      return true;
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Could not start chat: $e'),
        backgroundColor: Colors.red,
      ));
      return false;
    }
  }
}
