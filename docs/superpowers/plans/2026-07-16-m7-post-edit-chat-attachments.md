# M-7 Post Edit & Chat Image Attachments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the two deferred M-7 findings in `docs/QA_AUDIT_REPORT.md` — let a post author edit their caption/location (with an "edited" indicator), and let chat users attach an image (camera or gallery) to a message.

**Architecture:** Both features are additive to the existing `PostProvider`/`ChatProvider` (in `lib/shared/providers/real_providers.dart`) and reuse established patterns 1:1 — `updatePost` mirrors the mock-splice/real-Firestore-write split already used by `likePost`/`unlikePost`; `uploadChatImage` is a byte-for-byte copy of `uploadPostImage` with a different Storage path. No new screens are added to the router — `EditPostScreen` is reached via a plain `Navigator.push`, matching how `PostDetailsScreen` itself is already reached (this codebase does not route every screen through GoRouter).

**Tech Stack:** Flutter/Dart, Provider (ChangeNotifier), Cloud Firestore, Firebase Storage, `image_picker`, `cached_network_image` (via the existing `CachedFeedImage` wrapper), `mocktail` + `fake_cloud_firestore` for tests.

## Global Constraints

- No Firestore rules, Storage rules, or Cloud Functions changes — both features are confirmed to work under the existing rules (post owner already has full update rights; `user_uploads/{uid}/{folder}/{file}` is already permitted for images ≤10MB). Do not touch `firestore.rules` or `storage.rules` in this plan.
- No new pubspec dependencies — `image_picker` and `cached_network_image` (via `CachedFeedImage`) are already used elsewhere in the app.
- Post edit is **text-only** (caption + location). Do not add a media picker to `EditPostScreen`.
- Chat attachments are **images only** (camera + gallery). Do not add video support.
- Follow this codebase's established test-flakiness policy (`test/widgets/cached_image_test.dart`'s own doc comment): never let a widget test wait (`pumpAndSettle`) on a real network-image fetch. Use a single bounded `tester.pump()` instead wherever a `CachedFeedImage`/`CachedNetworkImage` is on screen.
- Every `flutter analyze` run in this plan must come back with **zero issues** (the repo is currently fully clean); every `flutter test` run must show **all tests passing** before moving to the next task.
- Commit after each task with a `feat(m7): ...` or `test(m7): ...` message, `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

### Task 1: `PostModel.editedAt` field

**Files:**
- Modify: `lib/shared/models/models.dart:118-179` (`PostModel` class)
- Test: `test/models/post_model_test.dart` (new)

**Interfaces:**
- Produces: `PostModel.editedAt` (`DateTime?`, defaults to `null`), read/written by `PostModel.fromFirestore`/`toFirestore`. Later tasks (`PostProvider.updatePost`, `EditPostScreen`) construct `PostModel` instances passing `editedAt`.

- [ ] **Step 1: Write the failing model test**

Create `test/models/post_model_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/models/models.dart';

/// Regression coverage for M-7 post edit: a post gains an `editedAt`
/// timestamp only once it's been edited, and it round-trips through
/// Firestore as a proper DateTime (not left as a raw Timestamp).
void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  PostModel buildPost({DateTime? editedAt}) => PostModel(
        id: 'p1',
        authorId: 'u1',
        authorName: 'Alex',
        caption: 'hello',
        createdAt: DateTime(2026, 1, 1),
        editedAt: editedAt,
      );

  group('PostModel.editedAt round-trip', () {
    test('a never-edited post round-trips with editedAt null', () async {
      final post = buildPost();
      await db.collection('posts').doc('p1').set(post.toFirestore());

      final snap = await db.collection('posts').doc('p1').get();
      final parsed = PostModel.fromFirestore(snap);

      expect(parsed.editedAt, isNull);
    });

    test('an edited post round-trips editedAt as a DateTime', () async {
      final post = buildPost(editedAt: DateTime(2026, 7, 16, 12, 0));
      await db.collection('posts').doc('p1').set(post.toFirestore());

      final snap = await db.collection('posts').doc('p1').get();
      final parsed = PostModel.fromFirestore(snap);

      expect(parsed.editedAt, DateTime(2026, 7, 16, 12, 0));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/post_model_test.dart`
Expected: FAIL — `editedAt` is not a named parameter of `PostModel` (compile error: "No named parameter with the name 'editedAt'").

- [ ] **Step 3: Add `editedAt` to `PostModel`**

In `lib/shared/models/models.dart`, inside `class PostModel` (starts at line 118):

Change the field list (after `final DateTime createdAt;` at line 135) to add:

```dart
  final DateTime createdAt;
  final DateTime? editedAt; // set on first edit (M-7); null if never edited
```

Change the constructor (lines 137-144) from:

```dart
  const PostModel({
    required this.id, required this.authorId, required this.authorName,
    this.authorPhotoUrl, this.mediaUrls = const [], this.mediaType = 'text',
    this.thumbnailUrl, this.aspectRatio, this.durationMs,
    this.caption = '', this.location, this.likeCount = 0,
    this.commentCount = 0, this.isReported = false, this.reportCount = 0,
    this.groupId, required this.createdAt,
  });
```

to:

```dart
  const PostModel({
    required this.id, required this.authorId, required this.authorName,
    this.authorPhotoUrl, this.mediaUrls = const [], this.mediaType = 'text',
    this.thumbnailUrl, this.aspectRatio, this.durationMs,
    this.caption = '', this.location, this.likeCount = 0,
    this.commentCount = 0, this.isReported = false, this.reportCount = 0,
    this.groupId, required this.createdAt, this.editedAt,
  });
```

Change `fromFirestore` (lines 146-168) from:

```dart
  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['createdAt'] is Timestamp) d['createdAt'] = (d['createdAt'] as Timestamp).toDate();
    return PostModel(
      id: doc.id,
      authorId: d['authorId'] ?? '',
      authorName: d['authorName'] ?? '',
      authorPhotoUrl: d['authorPhotoUrl'],
      mediaUrls: List<String>.from(d['mediaUrls'] ?? []),
      mediaType: d['mediaType'] ?? 'text',
      thumbnailUrl: d['thumbnailUrl'],
      aspectRatio: (d['aspectRatio'] as num?)?.toDouble(),
      durationMs: (d['durationMs'] as num?)?.toInt(),
      caption: d['caption'] ?? '',
      location: d['location'],
      likeCount: d['likeCount'] ?? 0,
      commentCount: d['commentCount'] ?? 0,
      isReported: d['isReported'] ?? false,
      reportCount: d['reportCount'] ?? 0,
      groupId: d['groupId'],
      createdAt: d['createdAt'] is DateTime ? d['createdAt'] : DateTime.now(),
    );
  }
```

to:

```dart
  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['createdAt'] is Timestamp) d['createdAt'] = (d['createdAt'] as Timestamp).toDate();
    if (d['editedAt'] is Timestamp) d['editedAt'] = (d['editedAt'] as Timestamp).toDate();
    return PostModel(
      id: doc.id,
      authorId: d['authorId'] ?? '',
      authorName: d['authorName'] ?? '',
      authorPhotoUrl: d['authorPhotoUrl'],
      mediaUrls: List<String>.from(d['mediaUrls'] ?? []),
      mediaType: d['mediaType'] ?? 'text',
      thumbnailUrl: d['thumbnailUrl'],
      aspectRatio: (d['aspectRatio'] as num?)?.toDouble(),
      durationMs: (d['durationMs'] as num?)?.toInt(),
      caption: d['caption'] ?? '',
      location: d['location'],
      likeCount: d['likeCount'] ?? 0,
      commentCount: d['commentCount'] ?? 0,
      isReported: d['isReported'] ?? false,
      reportCount: d['reportCount'] ?? 0,
      groupId: d['groupId'],
      createdAt: d['createdAt'] is DateTime ? d['createdAt'] : DateTime.now(),
      editedAt: d['editedAt'] is DateTime ? d['editedAt'] as DateTime : null,
    );
  }
```

Change `toFirestore` (lines 170-178) from:

```dart
  Map<String, dynamic> toFirestore() => {
    'authorId': authorId, 'authorName': authorName, 'authorPhotoUrl': authorPhotoUrl,
    'mediaUrls': mediaUrls, 'mediaType': mediaType,
    'thumbnailUrl': thumbnailUrl, 'aspectRatio': aspectRatio, 'durationMs': durationMs,
    'caption': caption,
    'location': location, 'likeCount': likeCount, 'commentCount': commentCount,
    'isReported': isReported, 'reportCount': reportCount, 'groupId': groupId,
    'createdAt': createdAt,
  };
```

to:

```dart
  Map<String, dynamic> toFirestore() => {
    'authorId': authorId, 'authorName': authorName, 'authorPhotoUrl': authorPhotoUrl,
    'mediaUrls': mediaUrls, 'mediaType': mediaType,
    'thumbnailUrl': thumbnailUrl, 'aspectRatio': aspectRatio, 'durationMs': durationMs,
    'caption': caption,
    'location': location, 'likeCount': likeCount, 'commentCount': commentCount,
    'isReported': isReported, 'reportCount': reportCount, 'groupId': groupId,
    'createdAt': createdAt, 'editedAt': editedAt,
  };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/post_model_test.dart`
Expected: PASS (2/2 tests)

- [ ] **Step 5: Run full analyze + full suite (regression check)**

Run: `flutter analyze && flutter test`
Expected: analyze — "No issues found!"; test — all tests pass (333 existing + 2 new = 335)

- [ ] **Step 6: Commit**

```bash
git add lib/shared/models/models.dart test/models/post_model_test.dart
git commit -m "$(cat <<'EOF'
feat(m7): add PostModel.editedAt for post-edit tracking

Nullable, backward-compatible field — every existing post round-trips
with editedAt null. Timestamp normalization mirrors the existing
createdAt handling in fromFirestore/toFirestore.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `PostProvider.updatePost`

**Files:**
- Modify: `lib/shared/providers/real_providers.dart` (add a method inside `class PostProvider`, after `deletePost` at line 1112 and before `reportContent` at line 1114)
- Test: `test/providers/post_provider_test.dart` (add a group)

**Interfaces:**
- Consumes: `PostModel.editedAt` (Task 1).
- Produces: `Future<void> updatePost(String postId, {required String caption, String? location})` on `PostProvider` — used by Task 3's `EditPostScreen`.

- [ ] **Step 1: Write the failing provider contract test**

In `test/providers/post_provider_test.dart`, add this group (this file already has a `setUp` creating `late FakeFirebaseFirestore db;` and `const postId = 'post-abc';` — add the new group anywhere at the top level alongside the existing `group('Likes', ...)`):

```dart
  group('Post edit (M-7)', () {
    test('updating a post writes caption/location/editedAt', () async {
      await db.collection('posts').doc(postId).set({
        'caption': 'original', 'location': null, 'authorId': uid,
      });

      // Mirrors PostProvider.updatePost's real-mode write.
      await db.collection('posts').doc(postId).update({
        'caption': 'edited caption',
        'location': 'DXB',
        'editedAt': FieldValue.serverTimestamp(),
      });

      final snap = await db.collection('posts').doc(postId).get();
      expect(snap.data()!['caption'], 'edited caption');
      expect(snap.data()!['location'], 'DXB');
      expect(snap.data()!['editedAt'], isNotNull);
    });
  });
```

- [ ] **Step 2: Run test to verify it passes as a data-layer contract test**

Run: `flutter test test/providers/post_provider_test.dart`
Expected: PASS — this test only exercises `fake_cloud_firestore` directly (matching every other group in this file, per its own doc comment: "our provider uses singleton Firestore, so we validate the data-layer contract directly against fake Firestore"), so it passes before `updatePost` even exists. It documents the exact write shape the method must produce.

- [ ] **Step 3: Implement `updatePost` on `PostProvider`**

In `lib/shared/providers/real_providers.dart`, immediately after `deletePost`'s closing `}` (line 1112) and before the `// ── Generic content reporting` comment (line 1114), insert:

```dart

  /// Updates an existing post's caption/location (M-7 post edit). Media is
  /// intentionally not editable here. Owner-only is enforced server-side by
  /// the existing posts rule (`isOwner(resource.data.authorId)`) — no rules
  /// change needed.
  Future<void> updatePost(String postId,
      {required String caption, String? location}) async {
    if (isMock) {
      final i = _feed.indexWhere((p) => p.id == postId);
      if (i != -1) {
        final p = _feed[i];
        _feed[i] = PostModel(
          id: p.id, authorId: p.authorId, authorName: p.authorName,
          authorPhotoUrl: p.authorPhotoUrl, mediaUrls: p.mediaUrls,
          mediaType: p.mediaType, thumbnailUrl: p.thumbnailUrl,
          aspectRatio: p.aspectRatio, durationMs: p.durationMs,
          caption: caption, location: location, likeCount: p.likeCount,
          commentCount: p.commentCount, isReported: p.isReported,
          reportCount: p.reportCount, groupId: p.groupId,
          createdAt: p.createdAt, editedAt: DateTime.now(),
        );
      }
      notifyListeners();
      return;
    }
    if (_uid == null) return;
    await _db.collection('posts').doc(postId).update({
      'caption': caption,
      'location': location,
      'editedAt': FieldValue.serverTimestamp(),
    });
    // No manual _feed splice: the live snapshot listener already delivers
    // the updated doc, mirroring likePost/unlikePost's real-mode convention
    // (see their comments a few methods up).
  }
```

- [ ] **Step 4: Run test + full regression**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all tests pass (335, unchanged from Task 1 since this test was already passing)

- [ ] **Step 5: Commit**

```bash
git add lib/shared/providers/real_providers.dart test/providers/post_provider_test.dart
git commit -m "$(cat <<'EOF'
feat(m7): add PostProvider.updatePost (caption + location edit)

Mock mode splices the local feed cache (matching likePost/unlikePost's
mock convention); real mode just writes to Firestore and relies on the
live feed snapshot listener to deliver the update, same as every other
real-mode mutation in this provider. No rules change — posts are
already fully owner-editable.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `EditPostScreen`

**Files:**
- Create: `lib/features/home/edit_post_screen.dart`
- Modify: `test/helpers/fixtures.dart:68-80` (extend `buildPost` with `mediaUrls`/`location` params)
- Test: `test/widgets/edit_post_screen_test.dart` (new)

**Interfaces:**
- Consumes: `PostProvider.updatePost` (Task 2), `PostModel` (Task 1's `editedAt` field).
- Produces: `EditPostScreen({required PostModel post})` — a `StatefulWidget`. On successful save it calls `Navigator.pop(context, updatedPost)` where `updatedPost` is a `PostModel` with `caption`/`location`/`editedAt` updated. Task 4 and Task 5 push this screen and consume that return value.

- [ ] **Step 1: Extend the `buildPost` fixture**

In `test/helpers/fixtures.dart`, change (lines 68-80):

```dart
PostModel buildPost({
  String id = 'post-1',
  String authorId = 'user-1',
  String authorName = 'Test User',
  String caption = 'A test post',
}) =>
    PostModel(
      id: id,
      authorId: authorId,
      authorName: authorName,
      caption: caption,
      createdAt: DateTime(2026, 1, 1),
    );
```

to:

```dart
PostModel buildPost({
  String id = 'post-1',
  String authorId = 'user-1',
  String authorName = 'Test User',
  String caption = 'A test post',
  List<String> mediaUrls = const [],
  String? location,
}) =>
    PostModel(
      id: id,
      authorId: authorId,
      authorName: authorName,
      caption: caption,
      mediaUrls: mediaUrls,
      location: location,
      createdAt: DateTime(2026, 1, 1),
    );
```

- [ ] **Step 2: Write the failing widget test**

Create `test/widgets/edit_post_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/providers/post_provider.dart';
import 'package:flyconnect/features/home/edit_post_screen.dart';

import '../helpers/fixtures.dart';

class _MockPostProvider extends Mock implements PostProvider {}

Future<void> _pump(WidgetTester tester, PostProvider postProvider,
    {required List<String> mediaUrls, String caption = 'original caption', String? location}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PostProvider>.value(value: postProvider),
      ],
      child: MaterialApp(
        home: EditPostScreen(
          post: buildPost(caption: caption, mediaUrls: mediaUrls, location: location),
        ),
      ),
    ),
  );
}

void main() {
  late _MockPostProvider postProvider;

  setUp(() {
    postProvider = _MockPostProvider();
  });

  group('M-7: post edit', () {
    testWidgets('fields pre-fill from the passed post', (tester) async {
      await _pump(tester, postProvider,
          mediaUrls: const [], caption: 'my original caption', location: 'DXB');
      await tester.pumpAndSettle();

      expect(find.text('my original caption'), findsOneWidget);
      expect(find.text('DXB'), findsOneWidget);
    });

    testWidgets('Save calls updatePost with the edited values', (tester) async {
      when(() => postProvider.updatePost(any(),
              caption: any(named: 'caption'), location: any(named: 'location')))
          .thenAnswer((_) async {});

      await _pump(tester, postProvider, mediaUrls: const [], caption: 'old', location: null);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'new caption');
      await tester.tap(find.text('Save'));
      await tester.pump();

      verify(() => postProvider.updatePost('post-1',
          caption: 'new caption', location: null)).called(1);
    });

    testWidgets('on a text-only post, clearing the caption blocks save',
        (tester) async {
      await _pump(tester, postProvider, mediaUrls: const [], caption: 'old', location: null);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('A text post needs a caption.'), findsOneWidget);
      verifyNever(() => postProvider.updatePost(any(),
          caption: any(named: 'caption'), location: any(named: 'location')));
    });

    testWidgets('on a media post, an empty caption is allowed to save',
        (tester) async {
      when(() => postProvider.updatePost(any(),
              caption: any(named: 'caption'), location: any(named: 'location')))
          .thenAnswer((_) async {});

      await _pump(tester, postProvider,
          mediaUrls: const ['https://example.com/photo.jpg'], caption: 'old', location: null);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('A text post needs a caption.'), findsNothing);
      verify(() => postProvider.updatePost('post-1',
          caption: '', location: null)).called(1);
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/widgets/edit_post_screen_test.dart`
Expected: FAIL — `package:flyconnect/features/home/edit_post_screen.dart` does not exist (import error).

- [ ] **Step 4: Create `EditPostScreen`**

Create `lib/features/home/edit_post_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/providers/post_provider.dart';
import '../../shared/models/models.dart';

/// Caption + location edit for an existing post (M-7). Media is not
/// editable here — see docs/superpowers/specs/2026-07-16-m7-post-edit-chat-attachments-design.md.
/// On success, pops with the updated [PostModel] so the caller (a post
/// menu on a screen that doesn't have a live Firestore listener, like
/// PostDetailsScreen) can refresh its local display without a full reload.
class EditPostScreen extends StatefulWidget {
  final PostModel post;
  const EditPostScreen({super.key, required this.post});

  @override
  State<EditPostScreen> createState() => _EditPostScreenState();
}

class _EditPostScreenState extends State<EditPostScreen> {
  late final TextEditingController _captionController;
  late final TextEditingController _locationController;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.post.caption);
    _locationController =
        TextEditingController(text: widget.post.location ?? '');
  }

  @override
  void dispose() {
    _captionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final caption = _captionController.text.trim();
    final hasMedia = widget.post.mediaUrls.isNotEmpty;
    if (caption.isEmpty && !hasMedia) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('A text post needs a caption.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _loading = true);
    final location =
        _locationController.text.trim().isEmpty ? null : _locationController.text.trim();
    try {
      await context
          .read<PostProvider>()
          .updatePost(widget.post.id, caption: caption, location: location);
      if (!mounted) return;
      final updated = PostModel(
        id: widget.post.id,
        authorId: widget.post.authorId,
        authorName: widget.post.authorName,
        authorPhotoUrl: widget.post.authorPhotoUrl,
        mediaUrls: widget.post.mediaUrls,
        mediaType: widget.post.mediaType,
        thumbnailUrl: widget.post.thumbnailUrl,
        aspectRatio: widget.post.aspectRatio,
        durationMs: widget.post.durationMs,
        caption: caption,
        location: location,
        likeCount: widget.post.likeCount,
        commentCount: widget.post.commentCount,
        isReported: widget.post.isReported,
        reportCount: widget.post.reportCount,
        groupId: widget.post.groupId,
        createdAt: widget.post.createdAt,
        editedAt: DateTime.now(),
      );
      Navigator.pop(context, updated);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not save changes. Please try again.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.dark),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Center(child: Text('Edit Post', style: AppTextStyles.h4)),
              ),
              ElevatedButton(
                onPressed: _loading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4F53C),
                  foregroundColor: const Color(0xFF1A1D27),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  minimumSize: const Size(80, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF1A1D27)),
                      )
                    : const Text('Save'),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  TextField(
                    controller: _captionController,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 2000,
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                    decoration: const InputDecoration(
                      hintText: "What's on your mind?",
                      hintStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Color(0xFFF5F5F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(color: Color(0xFF1A1D27), width: 1),
                      ),
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _locationController,
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.dark),
                        decoration: InputDecoration(
                          hintText: 'Add location',
                          hintStyle:
                              AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/widgets/edit_post_screen_test.dart`
Expected: PASS (4/4 tests)

- [ ] **Step 6: Run full analyze + full suite**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all tests pass (335 + 4 new = 339)

- [ ] **Step 7: Commit**

```bash
git add lib/features/home/edit_post_screen.dart test/helpers/fixtures.dart test/widgets/edit_post_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(m7): add EditPostScreen (caption + location, no media picker)

Mirrors create_post_screen's caption-field styling. Save is blocked
only when the post would end up with neither a caption nor media
(matches create_post's own empty-post guard) — an image-only post may
keep an empty caption. Pops with the updated PostModel so a caller
without a live Firestore listener (PostDetailsScreen) can refresh
in place.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Wire Edit into `home_screen.dart`'s post menu + "edited" label

**Files:**
- Modify: `lib/features/home/home_screen.dart`

**Interfaces:**
- Consumes: `EditPostScreen` (Task 3).

- [ ] **Step 1: Add the import**

In `lib/features/home/home_screen.dart`, add this line after the existing `import 'post_details_screen.dart';` (around line 18):

```dart
import 'edit_post_screen.dart';
```

- [ ] **Step 2: Add the "edited" label**

Change line 705 from:

```dart
            Text(timeago.format(p.createdAt), style: AppTextStyles.caption),
```

to:

```dart
            Text(
              '${timeago.format(p.createdAt)}${p.editedAt != null ? ' · edited' : ''}',
              style: AppTextStyles.caption,
            ),
```

- [ ] **Step 3: Add the Edit menu tile + handler**

Find the `if (isOwn) ... else ...` block inside `_showOptions` (around lines 633-644):

```dart
        if (isOwn)
          ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete post', style: TextStyle(color: Colors.red)),
            onTap: () { Navigator.pop(context); _confirmDeletePost(); })
        else
          ListTile(leading: const Icon(Icons.flag_outlined, color: Colors.red),
            title: const Text('Report post', style: TextStyle(color: Colors.red)),
            onTap: () async {
```

Change the `if (isOwn)` branch to include Edit above Delete:

```dart
        if (isOwn) ...[
          ListTile(leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit post'),
            onTap: _editPost),
          ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete post', style: TextStyle(color: Colors.red)),
            onTap: () { Navigator.pop(context); _confirmDeletePost(); }),
        ] else
          ListTile(leading: const Icon(Icons.flag_outlined, color: Colors.red),
            title: const Text('Report post', style: TextStyle(color: Colors.red)),
            onTap: () async {
```

Add the `_editPost` method right before `_showOptions` (which starts around line 620):

```dart
  void _editPost() {
    Navigator.pop(context); // close the options sheet
    Navigator.push(context,
      MaterialPageRoute(builder: (_) => EditPostScreen(post: widget.post)));
  }

```

(No return-value handling needed here: the feed rebuilds `_PostCard` with a fresh `widget.post` once `updatePost` lands — via the live Firestore snapshot listener in real mode, or the mock-mode `_feed` splice — the same mechanism `likePost`/`unlikePost` already rely on.)

- [ ] **Step 4: Run full analyze + full suite**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all 339 tests still pass (no test in this file asserts on the exact bottom-sheet children count, so this is a safe additive change — verify by running the full suite, not just a targeted file).

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/home_screen.dart
git commit -m "$(cat <<'EOF'
feat(m7): wire Edit post into the home feed card menu

Adds an author-gated "Edit post" tile above "Delete post" and an
"· edited" suffix on the timestamp once editedAt is set. No manual
feed-cache patch needed — the live snapshot listener (or the mock-mode
splice in PostProvider.updatePost) already refreshes the card.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Wire Edit into `post_details_screen.dart` + local `_post` state

**Files:**
- Modify: `lib/features/home/post_details_screen.dart`

**Interfaces:**
- Consumes: `EditPostScreen` (Task 3).

- [ ] **Step 1: Add the import**

Add after the existing `import '../../shared/widgets/feed_video.dart';` (line 10):

```dart
import 'edit_post_screen.dart';
```

- [ ] **Step 2: Add local `_post` state**

This screen holds `widget.post` immutably and never re-subscribes to Firestore, unlike the home feed card — so an in-place edit needs its own local state to refresh without leaving the screen. Change the state class fields (lines 19-22) from:

```dart
class _PostDetailsScreenState extends State<PostDetailsScreen> {
  final TextEditingController _ctrl = TextEditingController();
  bool _isLiked = false;
  bool _isSaved = false;
  int _likeCount = 0;
```

to:

```dart
class _PostDetailsScreenState extends State<PostDetailsScreen> {
  final TextEditingController _ctrl = TextEditingController();
  bool _isLiked = false;
  bool _isSaved = false;
  int _likeCount = 0;
  late PostModel _post;
```

Change `initState` (lines 48-53) from:

```dart
  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
    _checkLike();
    _checkSaved();
  }
```

to:

```dart
  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _likeCount = widget.post.likeCount;
    _checkLike();
    _checkSaved();
  }
```

- [ ] **Step 3: Read caption/timestamp/edited-label from `_post`**

Change line 110 from:

```dart
              subtitle: Text(timeago.format(widget.post.createdAt)),
```

to:

```dart
              subtitle: Text(
                '${timeago.format(_post.createdAt)}${_post.editedAt != null ? ' · edited' : ''}',
              ),
```

Change line 161 from:

```dart
                TextSpan(text: widget.post.caption),
```

to:

```dart
                TextSpan(text: _post.caption),
```

- [ ] **Step 4: Add the Edit menu tile + handler**

Find the `if (isOwn) ... else ...` block inside `_showOptions` (lines 229-238):

```dart
      if (isOwn)
        ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red),
          title: const Text('Delete post', style: TextStyle(color: Colors.red)),
          onTap: () { Navigator.pop(context); _confirmDeletePost(); })
      else
        ListTile(leading: const Icon(Icons.flag_outlined, color: Colors.red), title: const Text('Report post'),
          onTap: () async {
```

Change to:

```dart
      if (isOwn) ...[
        ListTile(leading: const Icon(Icons.edit_outlined),
          title: const Text('Edit post'),
          onTap: _editPost),
        ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red),
          title: const Text('Delete post', style: TextStyle(color: Colors.red)),
          onTap: () { Navigator.pop(context); _confirmDeletePost(); }),
      ] else
        ListTile(leading: const Icon(Icons.flag_outlined, color: Colors.red), title: const Text('Report post'),
          onTap: () async {
```

Add the `_editPost` method right before `_showOptions` (which starts at line 227):

```dart
  Future<void> _editPost() async {
    Navigator.pop(context); // close the options sheet
    final updated = await Navigator.push<PostModel>(context,
      MaterialPageRoute(builder: (_) => EditPostScreen(post: _post)));
    if (updated != null && mounted) setState(() => _post = updated);
  }

```

- [ ] **Step 5: Run full analyze + full suite**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all 339 tests still pass (this file has no existing widget test suite — confirm no other file constructs `_PostDetailsScreenState` in a way this change would break; the full suite run covers that).

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/post_details_screen.dart
git commit -m "$(cat <<'EOF'
feat(m7): wire Edit post into the post details screen

PostDetailsScreen holds its post immutably with no live Firestore
listener (unlike the home feed card), so it needs its own local _post
state to reflect an edit without leaving the screen. Caption and the
timestamp/"edited" label now read from _post; _editPost() awaits
EditPostScreen's returned PostModel and setState()s it in.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `ChatProvider.uploadChatImage` + `sendMessage` empty-caption fix

**Files:**
- Modify: `lib/shared/providers/real_providers.dart` (inside `class ChatProvider`)
- Test: `test/providers/chat_provider_test.dart`

**Interfaces:**
- Produces: `Future<String?> uploadChatImage(Uint8List bytes)` on `ChatProvider` — used by Task 7's `conversation_screen.dart`. `sendMessage`'s existing signature (`sendMessage(String chatId, String text, {String? mediaUrl, String mediaType = 'text'})`) is unchanged; only its internal `lastMessage` value changes for the empty-caption-image case.

- [ ] **Step 1: Write the failing tests**

In `test/providers/chat_provider_test.dart`, inside the existing `group('Unread counts', ...)` block, extend the local `sendAsProvider` helper (lines 86-97) from:

```dart
    Future<void> sendAsProvider(String senderId, List<String> participants, String text) async {
      final chatRef = db.collection('chats').doc(chatId);
      final msgRef = chatRef.collection('messages').doc();
      final batch = db.batch();
      batch.set(msgRef, {'senderId': senderId, 'text': text, 'readBy': [senderId]});
      final chatUpdate = <String, dynamic>{'lastMessage': text};
      for (final uid in participants) {
        if (uid != senderId) chatUpdate['unreadCount.$uid'] = FieldValue.increment(1);
      }
      batch.update(chatRef, chatUpdate);
      await batch.commit();
    }
```

to:

```dart
    Future<void> sendAsProvider(String senderId, List<String> participants, String text,
        {String? mediaUrl, String mediaType = 'text'}) async {
      final chatRef = db.collection('chats').doc(chatId);
      final msgRef = chatRef.collection('messages').doc();
      final batch = db.batch();
      batch.set(msgRef, {
        'senderId': senderId, 'text': text, 'mediaUrl': mediaUrl,
        'mediaType': mediaType, 'readBy': [senderId],
      });
      final chatUpdate = <String, dynamic>{
        'lastMessage': text.isEmpty && mediaType == 'image' ? '📷 Photo' : text,
      };
      for (final uid in participants) {
        if (uid != senderId) chatUpdate['unreadCount.$uid'] = FieldValue.increment(1);
      }
      batch.update(chatRef, chatUpdate);
      await batch.commit();
    }
```

Then add a new test right after the existing `'unreadCount accumulates across multiple unread messages'` test (after line 124, still inside `group('Unread counts', ...)`):

```dart

    test('sending an image with no caption still increments unreadCount and shows a photo preview',
        () async {
      await db.collection('chats').doc(chatId).set({
        'participants': [me, them],
        'unreadCount': {me: 0, them: 0},
      });

      await sendAsProvider(me, [me, them], '',
          mediaUrl: 'https://example.com/photo.jpg', mediaType: 'image');

      final chat = await db.collection('chats').doc(chatId).get();
      expect(chat.data()!['unreadCount'][them], 1);
      expect(chat.data()!['lastMessage'], '📷 Photo');

      final msgs = await db.collection('chats').doc(chatId).collection('messages').get();
      expect(msgs.docs.first['mediaUrl'], 'https://example.com/photo.jpg');
      expect(msgs.docs.first['mediaType'], 'image');
    });
```

- [ ] **Step 2: Run test to verify it passes as a data-layer contract test**

Run: `flutter test test/providers/chat_provider_test.dart`
Expected: PASS — same rationale as Task 2's provider test: this validates the write shape `sendMessage` must produce, independent of whether `uploadChatImage` exists yet.

- [ ] **Step 3: Implement `uploadChatImage` and the `sendMessage` lastMessage tweak**

In `lib/shared/providers/real_providers.dart`, inside `class ChatProvider`, change `sendMessage`'s `chatUpdate` construction (lines 1376-1379) from:

```dart
    final chatUpdate = <String, dynamic>{
      'lastMessage': text, 'lastMessageSenderId': _uid,
      'lastMessageAt': FieldValue.serverTimestamp(),
    };
```

to:

```dart
    final chatUpdate = <String, dynamic>{
      // An image sent with no caption would otherwise leave the chat list's
      // "last message" preview blank (M-7 chat attachments).
      'lastMessage': text.isEmpty && mediaType == 'image' ? '📷 Photo' : text,
      'lastMessageSenderId': _uid,
      'lastMessageAt': FieldValue.serverTimestamp(),
    };
```

Then, immediately after `sendMessage`'s closing `}` (line 1386) and before `markAsRead` (line 1388), insert:

```dart

  /// Upload a chat image to Firebase Storage and return the public download
  /// URL. Mirrors PostProvider.uploadPostImage exactly (M-7 chat attachments).
  /// Path: user_uploads/{uid}/chat/{timestamp}.png
  Future<String?> uploadChatImage(Uint8List bytes) async {
    if (isMock) return null;
    if (_uid == null) return null;
    try {
      final compressed = await compressForUpload(bytes);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref('user_uploads/$_uid/chat/$ts.png');
      await ref.putData(compressed, SettableMetadata(contentType: 'image/png'));
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }
```

- [ ] **Step 4: Run test to verify it passes + full regression**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all tests pass (339 + 1 new = 340)

- [ ] **Step 5: Commit**

```bash
git add lib/shared/providers/real_providers.dart test/providers/chat_provider_test.dart
git commit -m "$(cat <<'EOF'
feat(m7): add ChatProvider.uploadChatImage; fix empty-caption image preview

uploadChatImage mirrors uploadPostImage exactly (compress, putData,
getDownloadURL) at user_uploads/{uid}/chat/. Bonus fix directly caused
by allowing images with no caption: sendMessage's chatUpdate now sets
lastMessage to a "📷 Photo" placeholder instead of an empty string, so
the chat list preview isn't blank for image-only messages.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `conversation_screen.dart` — attach button, picker sheet, image bubbles, fullscreen viewer

**Files:**
- Modify: `lib/features/chat/conversation_screen.dart`
- Test: `test/widgets/conversation_screen_test.dart` (new)

**Interfaces:**
- Consumes: `ChatProvider.uploadChatImage` and `sendMessage` (Task 6).

- [ ] **Step 1: Write the failing widget test**

Create `test/widgets/conversation_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/providers/chat_provider.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/shared/widgets/cached_image.dart';
import 'package:flyconnect/features/chat/conversation_screen.dart';

import '../helpers/fixtures.dart';

class _MockChatProvider extends Mock implements ChatProvider {}

class _MockAuthProvider extends Mock implements AuthProvider {}

Future<void> _pump(WidgetTester tester, ChatProvider chatProvider, AuthProvider authProvider) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: const MaterialApp(
        home: ConversationScreen(chatId: 'chat-1', otherName: 'Sam', otherUid: 'user-b'),
      ),
    ),
  );
}

void main() {
  late _MockChatProvider chatProvider;
  late _MockAuthProvider authProvider;

  setUp(() {
    chatProvider = _MockChatProvider();
    authProvider = _MockAuthProvider();
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'user-a'));
    when(() => chatProvider.markAsRead(any())).thenAnswer((_) async {});
    when(() => chatProvider.markMessagesRead(any())).thenAnswer((_) async {});
    when(() => chatProvider.watchTyping(any())).thenAnswer((_) => Stream.value(const {}));
  });

  MessageModel textMessage() => MessageModel(
      id: 'm1',
      chatId: 'chat-1',
      senderId: 'user-b',
      senderName: 'Sam',
      text: 'hey there',
      createdAt: DateTime(2026, 1, 1));

  MessageModel imageMessage() => MessageModel(
      id: 'm2',
      chatId: 'chat-1',
      senderId: 'user-b',
      senderName: 'Sam',
      text: '',
      mediaUrl: 'https://example.com/photo.jpg',
      mediaType: 'image',
      createdAt: DateTime(2026, 1, 1));

  group('M-7: chat image attachments', () {
    testWidgets('a text message renders text and no image bubble', (tester) async {
      when(() => chatProvider.watchMessages(any()))
          .thenAnswer((_) => Stream.value([textMessage()]));

      await _pump(tester, chatProvider, authProvider);
      // A single bounded pump, not pumpAndSettle: this codebase deliberately
      // avoids waiting on real network-image fetches in widget tests (see
      // test/widgets/cached_image_test.dart's own doc comment).
      await tester.pump();
      await tester.pump();

      expect(find.text('hey there'), findsOneWidget);
      expect(find.byType(CachedFeedImage), findsNothing);
    });

    testWidgets('an image message renders an image bubble', (tester) async {
      when(() => chatProvider.watchMessages(any()))
          .thenAnswer((_) => Stream.value([imageMessage()]));

      await _pump(tester, chatProvider, authProvider);
      await tester.pump();
      await tester.pump();

      expect(find.byType(CachedFeedImage), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/conversation_screen_test.dart`
Expected: FAIL — the second test fails because no `CachedFeedImage` is rendered for an image message yet (`conversation_screen.dart` currently only renders `Text(m.text, ...)`).

- [ ] **Step 3: Add imports**

In `lib/features/chat/conversation_screen.dart`, add after the existing `import '../../shared/models/models.dart';` (line 9):

```dart
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../../shared/widgets/cached_image.dart';
```

- [ ] **Step 4: Add the picker/upload/fullscreen methods**

Insert these three new methods right after `_scrollToBottom` (which ends at line 66) and before `_showConversationMenu` (line 68):

```dart

  Future<void> _pickAndSendImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _sending = true);
    try {
      final url = await context.read<ChatProvider>().uploadChatImage(bytes);
      if (url == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Image upload failed. Please try again.'),
          backgroundColor: Colors.red,
        ));
        return;
      }
      final caption = _ctrl.text.trim();
      _ctrl.clear();
      await context
          .read<ChatProvider>()
          .sendMessage(widget.chatId, caption, mediaUrl: url, mediaType: 'image');
      if (!mounted) return;
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send image: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () {
              Navigator.pop(context);
              _pickAndSendImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () {
              Navigator.pop(context);
              _pickAndSendImage(ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  void _openFullscreenImage(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            child: CachedFeedImage(url: url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 5: Add the attach button to the input row**

Change (lines 268-269):

```dart
          child: Row(children: [
            // Image attach hidden for v1.0 — image messages not yet wired to Storage.
            Expanded(child: TextField(
```

to:

```dart
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.dark),
              tooltip: 'Attach photo',
              onPressed: _sending ? null : _showAttachSheet,
            ),
            Expanded(child: TextField(
```

- [ ] **Step 6: Render image bubbles**

Change the message bubble's inner `Column` (lines 240-257) from:

```dart
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        if (!isMe && widget.isGroup) Text(m.senderName,
                          // Sender label sits on Colors.grey.shade100 (≈ white)
                          // for incoming bubbles — primary fails contrast there.
                          // AppColors.dark gives 13.6:1 and reads clearly.
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.dark)),
                        Text(m.text, style: TextStyle(color: isMe ? AppColors.dark : Colors.black87, fontSize: 15)),
                        const SizedBox(height: 2),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(timeago.format(m.createdAt, allowFromNow: true),
                            style: TextStyle(fontSize: 10, color: isMe ? AppColors.dark.withValues(alpha: 0.6) : Colors.grey)),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            Icon(m.readBy.length > 1 ? Icons.done_all : Icons.done,
                              size: 14, color: AppColors.dark.withValues(alpha: 0.7)),
                          ],
                        ]),
                      ]),
```

to:

```dart
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        if (!isMe && widget.isGroup) Text(m.senderName,
                          // Sender label sits on Colors.grey.shade100 (≈ white)
                          // for incoming bubbles — primary fails contrast there.
                          // AppColors.dark gives 13.6:1 and reads clearly.
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.dark)),
                        if (m.mediaType == 'image' && m.mediaUrl != null) ...[
                          GestureDetector(
                            onTap: () => _openFullscreenImage(m.mediaUrl!),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedFeedImage(
                                url: m.mediaUrl!,
                                width: 200,
                                height: 200,
                                fit: BoxFit.cover,
                                placeholder: Container(
                                  width: 200, height: 200, color: Colors.grey.shade200,
                                  child: const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2))),
                                errorWidget: Container(
                                  width: 200, height: 200, color: Colors.grey.shade200,
                                  child: const Icon(Icons.broken_image_outlined, color: Colors.grey)),
                              ),
                            ),
                          ),
                          if (m.text.isNotEmpty) const SizedBox(height: 6),
                        ],
                        if (m.text.isNotEmpty)
                          Text(m.text, style: TextStyle(color: isMe ? AppColors.dark : Colors.black87, fontSize: 15)),
                        const SizedBox(height: 2),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(timeago.format(m.createdAt, allowFromNow: true),
                            style: TextStyle(fontSize: 10, color: isMe ? AppColors.dark.withValues(alpha: 0.6) : Colors.grey)),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            Icon(m.readBy.length > 1 ? Icons.done_all : Icons.done,
                              size: 14, color: AppColors.dark.withValues(alpha: 0.7)),
                          ],
                        ]),
                      ]),
```

- [ ] **Step 7: Run test to verify it passes + full regression**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all tests pass (340 + 2 new = 342)

- [ ] **Step 8: Commit**

```bash
git add lib/features/chat/conversation_screen.dart test/widgets/conversation_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(m7): wire chat image attachments (camera/gallery) into conversation_screen

Replaces the "image attach hidden for v1.0" placeholder with a real
attach button -> camera/gallery source sheet -> upload -> send flow,
reusing ChatProvider.uploadChatImage. Image bubbles render via the
existing CachedFeedImage wrapper with a tap-to-fullscreen viewer
(InteractiveViewer in a Dialog). Text-only messages are unaffected.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Final verification, QA report update, spec/plan cross-check

**Files:**
- Modify: `docs/QA_AUDIT_REPORT.md` (M-7 row + Remediation Roadmap items 27/28)

**Interfaces:** None — this task only verifies and documents; no code interfaces are produced or consumed.

- [ ] **Step 1: Run the full verification suite**

Run: `flutter analyze && flutter test`
Expected: analyze — "No issues found!"; test — all 342 tests pass.

- [ ] **Step 2: Update `docs/QA_AUDIT_REPORT.md`**

In the M-7 row (Medium Findings table), change the "Deliberately deferred" sentences at the end of the M-7 cell from:

```
**Deliberately deferred: Post edit.** Confirmed there is no edit affordance anywhere and no `updatePost`/`editPost` provider method — this is a genuinely missing feature (new provider method + rules + a pre-filled edit screen), not a wiring gap like the others, so it needs its own ticket rather than a fold-in here. **Attachment picker in chat is still a no-op** — `ChatProvider.sendMessage` already accepts `mediaUrl`/`mediaType`, but there's no `uploadChatImage`-style method or `image_picker` UI yet; also deferred (Medium effort, no blocking dependency, straightforward next step using the same `uploadPostImage`/`uploadEventImage` pattern). 8 new/updated Dart tests, 331/331 tests pass, analyze clean (bar the same pre-existing 4 L-5 infos).
```

to:

```
**✅ Post edit — done 2026-07-16.** `PostModel.editedAt` + `PostProvider.updatePost` (caption + location only, no rules change — posts were already fully owner-editable) + new `EditPostScreen`, wired into both post menus (home feed card + post details) with an "· edited" label. Design: `docs/superpowers/specs/2026-07-16-m7-post-edit-chat-attachments-design.md`; plan: `docs/superpowers/plans/2026-07-16-m7-post-edit-chat-attachments.md`. **✅ Chat attachment picker — done 2026-07-16.** `ChatProvider.uploadChatImage` mirrors `uploadPostImage` exactly (`user_uploads/{uid}/chat/`, no storage-rules change); `conversation_screen.dart`'s attach button now opens a camera/gallery sheet, uploads, and sends an image message; image bubbles render via the existing `CachedFeedImage` wrapper with a tap-to-fullscreen viewer. Bonus fix: an image sent with no caption now sets the chat list's `lastMessage` to a "📷 Photo" placeholder instead of leaving it blank. 8 new Dart tests, 342/342 tests pass, analyze clean.
```

In the Remediation Roadmap table, change:

```
| 27 | Post edit (new feature: provider method + rules + edit screen) | 🟡 M-7 (deferred) | Large |
| 28 | Chat attachment picker (`uploadChatImage` + image_picker UI) | 🟡 M-7 (deferred) | Medium |
```

to:

```
| 27 | ~~Post edit (new feature: provider method + rules + edit screen)~~ ✅ **Done 2026-07-16** | 🟡 M-7 | done |
| 28 | ~~Chat attachment picker (`uploadChatImage` + image_picker UI)~~ ✅ **Done 2026-07-16** | 🟡 M-7 | done |
```

- [ ] **Step 3: Commit**

```bash
git add docs/QA_AUDIT_REPORT.md
git commit -m "$(cat <<'EOF'
docs(qa): M-7 fully closed — post edit + chat attachments shipped

Both previously-deferred M-7 items (post edit, chat image attachments)
are implemented and tested. No rules/Storage/Functions deploy required.
342/342 tests pass, analyze clean.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Plan Self-Review Notes (for the implementer's awareness)

- **Spec coverage:** Every spec requirement has a task — `editedAt` (Task 1), `updatePost` (Task 2), `EditPostScreen` (Task 3), both menu wirings + "edited" label (Tasks 4-5), `uploadChatImage` (Task 6), attach UI + image bubbles (Task 7), report/roadmap update (Task 8).
- **Deviation from the spec, and why:** the spec's Feature A section said "Add a GoRoute `'/edit-post'`... Menus call `context.push('/edit-post', extra: post)`." Grounding in the actual code showed `PostDetailsScreen` itself — the screen one hop away in the exact same navigation flow — is reached via a plain `Navigator.push(MaterialPageRoute(...))`, not a GoRoute; this codebase does not route every screen through GoRouter. Tasks 3-5 use `Navigator.push<PostModel>(MaterialPageRoute(...))` instead, which is more consistent with the file's own existing convention and avoids an unnecessary `state.extra` cast. This is a routing-mechanism detail the spec left generic, not a scope change — the feature (edit reachable from both menus, pre-filled, save updates and shows an indicator) is unchanged.
- **`home_screen.dart`'s feed card needs no `_post`-style local state** (unlike `post_details_screen.dart`) because `_PostCard.build()` reads `final p = widget.post;` fresh on every build, and the ListView.builder rebuilds it with a new `widget.post` once the feed listener (or mock splice) delivers the edit.
- **Type/signature consistency check:** `updatePost(String postId, {required String caption, String? location})` (Task 2) matches every call site in Task 3's `EditPostScreen`; `uploadChatImage(Uint8List bytes)` (Task 6) matches its call in Task 7; `EditPostScreen({required PostModel post})` matches both `Navigator.push` call sites in Tasks 4-5.
