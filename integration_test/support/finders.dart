import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Named [Finder]s for the widgets the E2E flows drive.
///
/// Keyed finders reference the exact `Key` strings a parallel agent is adding
/// to the screens. Where a widget has no key, we use a robust finder (byIcon /
/// widgetWithText / byType) resolved against the real screen structure — those
/// are documented at each site.
class F {
  F._();

  // ── Login (lib/features/auth/login_screen.dart) ──────────────
  static final loginEmail = find.byKey(const Key('login_email'));
  static final loginPassword = find.byKey(const Key('login_password'));
  static final loginSubmit = find.byKey(const Key('login_submit'));

  // ── Signup step 1 (lib/features/auth/signup_screen.dart) ─────
  static final signupName = find.byKey(const Key('signup_name'));
  static final signupEmail = find.byKey(const Key('signup_email'));
  static final signupPassword = find.byKey(const Key('signup_password'));
  static final signupTerms = find.byKey(const Key('signup_terms'));
  static final signupContinue = find.byKey(const Key('signup_continue'));
  static final signupRoleUser = find.byKey(const Key('signup_role_user'));
  static final signupRoleBusiness =
      find.byKey(const Key('signup_role_business'));
  // Step 2 final submit.
  static final signupCreate = find.byKey(const Key('signup_create'));

  /// The date-of-birth picker trigger. No key exists, so we match the InkWell
  /// by its placeholder text (crew step 1 only). The date picker opens on
  /// `initialDate = now - 25y`, which is already 18+, so the flow can just
  /// confirm with OK without changing the date.
  static final signupDob = find.text('Date of birth (must be 18+)');
  static final datePickerOk = find.text('OK');

  // ── Create post (lib/features/home/create_post_screen.dart) ──
  static final createPostCaption = find.byKey(const Key('createpost_caption'));
  static final createPostAudience =
      find.byKey(const Key('createpost_audience'));
  static final createPostShare = find.byKey(const Key('createpost_share'));

  /// The bottom-nav "+" that pushes /create-post (MainShell). It is a bare
  /// GestureDetector with an add icon — no key — so match the icon.
  static final createPostFab = find.byIcon(Icons.add_rounded);

  // ── Match (lib/features/match/match_screen.dart) ─────────────
  static final matchLike = find.byKey(const Key('match_like'));
  static final matchPass = find.byKey(const Key('match_pass'));
  static final matchMessage = find.byKey(const Key('match_message'));
  static final matchBanner = find.textContaining("It's a Match");

  // ── Conversation (lib/features/chat/conversation_screen.dart)
  static final chatInput = find.byKey(const Key('chat_input'));
  static final chatSend = find.byKey(const Key('chat_send'));

  // ── Other user's profile (lib/features/profile/profile_screen.dart)
  static final profileOverflow = find.byKey(const Key('profile_overflow'));
  static final profileBlock = find.byKey(const Key('profile_block'));

  // ── Post details (lib/features/home/post_details_screen.dart) ─
  /// Like toggle — the un-liked heart. After a like it becomes
  /// [Icons.favorite]. No key on this control, so match the icon.
  static final postLikeButton = find.byIcon(Icons.favorite_border);
  static final postLiked = find.byIcon(Icons.favorite);
  /// Comment composer on PostDetailsScreen. The hint ("Add a comment...") is an
  /// InputDecoration.hintText, not a Text widget, so it isn't findable by text;
  /// the comment bar is the only TextField on that screen, hence byType.last.
  /// Its send button is the sole send_rounded icon there.
  static final commentField = find.byType(TextField).last;
  static final commentSend = find.byIcon(Icons.send_rounded);

  // ── Common landmarks ─────────────────────────────────────────
  static final loginWelcome = find.text('Welcome back');
  static final homeFeedChip = find.text('Feed');
  static final businessUnderReview = find.text('Your business is under review');
  static final crewDealsTitle = find.text('Crew Deals');
  static final notificationsTitle = find.text('Notifications');
}
