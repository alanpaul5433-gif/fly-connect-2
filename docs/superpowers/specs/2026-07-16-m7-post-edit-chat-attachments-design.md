# M-7 wrap-up — Post edit & Chat image attachments

**Date:** 2026-07-16
**Status:** Approved design — ready for implementation plan
**Findings closed:** the two deferred items in QA_AUDIT_REPORT.md M-7 (post edit; chat attachment picker)

## Context

M-7 in the QA audit was mostly fixed earlier (chat mute, event cover image, 3 admin no-op buttons, plus the `_reject` notification gap). Two items were deliberately deferred as genuine new features rather than wiring gaps:

1. **Post edit** — there is no edit affordance and no `updatePost`/`editPost` provider method. Only whole-post delete exists.
2. **Chat attachment picker** — `ChatProvider.sendMessage` already accepts `mediaUrl`/`mediaType`, but there is no `uploadChatImage` method, no picker UI, and no image-bubble rendering. `conversation_screen.dart:269` carries a commented-out placeholder: *"Image attach hidden for v1.0 — image messages not yet wired to Storage."*

Both are self-contained, need **no Firestore-rules, Storage-rules, or deploy changes**, and ship with the next app build. They are independent of each other.

### Grounding facts (verified in code)

- **Firestore rules already permit** a post author to fully edit their own post: `posts` update allows `isOwner(resource.data.authorId)` (unaffected by the L-3 counter-forgery tightening, which only constrained the *non-owner* counter path). So a caption/location edit by the author needs **no rules change**.
- **Storage rules already permit** `user_uploads/{uid}/{folder}/{file=**}` for `isImage() && underSize(10)` — a `user_uploads/{uid}/chat/` path is already covered. **No storage-rules change.**
- `image_picker` is already a dependency (used by `create_post_screen`).
- `MessageModel` already has `mediaUrl` and `mediaType` fields; the send path already threads them. Only rendering + the picker + the upload method are missing.
- `PostModel` has `caption` and `location` but **no** `editedAt` field yet.
- Post `⋮` menus live in `lib/features/home/home_screen.dart` and `lib/features/home/post_details_screen.dart` (both currently offer Delete + Report; author-gating via the same `isOwn`/author check used to show Delete).

## Scope decisions (user-approved)

- **Post edit:** editable fields are **caption + location only** (text). Media is *not* editable. Track and show an **"edited"** indicator.
- **Chat attachments:** **images only** (no video), from **camera or gallery**. An image may be sent alone or with a text caption.

Explicitly out of scope (YAGNI): editing/replacing post media; text↔media type changes; video messages; edit-time-window limits; message editing.

---

## Feature A — Post edit

### Data model (`lib/shared/models/models.dart`)
Add `final DateTime? editedAt;` to `PostModel`.
- `fromFirestore`: `editedAt: (d['editedAt'] as Timestamp?)?.toDate()` (null when absent — backward compatible with every existing post).
- `toFirestore`: include `editedAt` only when non-null (avoid writing a null key on create).
- `const` constructor gains `this.editedAt`.

### Provider (`lib/shared/providers/real_providers.dart`)
`Future<void> updatePost(String postId, {required String caption, String? location})`
- Real path: `await _db.collection('posts').doc(postId).update({ 'caption': caption, 'location': location, 'editedAt': FieldValue.serverTimestamp() })`.
- Update the in-memory feed entry (replace the cached `PostModel` with `caption`/`location` set and `editedAt: DateTime.now()` as an optimistic local value) and `notifyListeners()`.
- Mock path (`isMock`): mutate the in-memory post; no Firestore.
- Owner-only is enforced server-side by existing rules; the UI only exposes Edit to the author, so no extra client guard is required beyond that gate.

### UI
1. **`lib/features/home/edit_post_screen.dart`** (new) — a `StatefulWidget` with a pre-filled caption field (`maxLength: 2000`, matching `create_post_screen`) and a location field, styled to match the compose screen. A **Save** action:
   - Validates the post won't become empty: block save only if the new caption is empty **and** the post has no media (`post.mediaUrls.isEmpty`), mirroring `create_post`'s `caption.isEmpty && !hasMedia` guard. An image-only post may keep an empty caption; a text-only post must keep a non-empty one.
   - `await context.read<PostProvider>().updatePost(...)` wrapped in try/catch; on success pop + a plain confirmation SnackBar; on failure an error SnackBar and stay on screen. No media picker.
2. **Both post `⋮` menus** (`home_screen.dart`, `post_details_screen.dart`): add an **"Edit post"** `ListTile` (pencil icon), rendered **only when the viewer is the author** (same condition already gating "Delete post"). Tapping navigates to `EditPostScreen` with the current `PostModel`.
3. **"edited" label**: wherever a post's timestamp is shown (feed card in `home_screen.dart`, header in `post_details_screen.dart`), append a subtle "· edited" when `post.editedAt != null`.

### Routing
Add a GoRoute `'/edit-post'` that reads the `PostModel` from `state.extra` and renders `EditPostScreen` (mirrors how other detail screens receive their model). Menus call `context.push('/edit-post', extra: post)`.

### Tests
- `test/providers/post_provider_test.dart`: `updatePost` writes `caption`/`location`/`editedAt` and updates the cached feed entry (fake_cloud_firestore).
- `test/models/*`: `PostModel` `editedAt` round-trip (present + absent).
- `test/widgets/edit_post_screen_test.dart`: fields pre-fill from the passed post; Save calls `updatePost` with edited values; on a text-only post an empty caption blocks save with a hint; on a media post an empty caption is allowed to save.

---

## Feature B — Chat image attachments

### Provider (`lib/shared/providers/real_providers.dart`)
`Future<String?> uploadChatImage(Uint8List bytes)` — mirrors `uploadPostImage` exactly:
- `isMock`/`_uid == null` → return null.
- `compressForUpload(bytes)` → `FirebaseStorage.instance.ref('user_uploads/$_uid/chat/$ts.png')` → `putData` (contentType `image/png`) → `getDownloadURL()`.
- try/catch → null on failure (caller surfaces an error).

### UI (`lib/features/chat/conversation_screen.dart`)
1. **Attach button**: replace the commented-out placeholder with a real photo/attach `IconButton` in the input row. On tap → a bottom-sheet source picker (**Camera** / **Gallery**) → `ImagePicker().pickImage(source:...)` → read bytes.
2. **Send flow**: set a sending/upload state → `uploadChatImage(bytes)` → on success `sendMessage(chatId, textController.text.trim(), mediaUrl: url, mediaType: 'image')` (text optional) → clear input; on upload failure show an error SnackBar and don't send. Reuses the existing `_sending` state pattern.
3. **Image bubbles**: in the message list, when `msg.mediaType == 'image' && msg.mediaUrl != null`, render a `CachedNetworkImage` (rounded, constrained max height) above any text; tap opens a fullscreen viewer (`Dialog` + `InteractiveViewer`). Text-only messages render unchanged.

### Rules / Storage
None. `sendMessage`'s message-create is already permitted; `user_uploads/{uid}/chat/` is already covered by the generic storage rule.

### Tests
- `test/providers/chat_provider_test.dart`: `sendMessage` with `mediaUrl`/`mediaType:'image'` writes a message doc carrying those fields (fake_cloud_firestore); the `unreadCount` increment (H-3) still fires for a media message.
- `test/widgets/conversation_screen_*`: an image message renders an image widget; a text message does not. (Storage upload itself isn't unit-testable with fake_cloud_firestore — covered by the contract that `sendMessage` receives the URL, not by faking `putData`.)

---

## Non-goals / risks

- **No deploy** — neither feature touches rules, indexes, or Cloud Functions.
- **Optimistic edit cache**: `updatePost` sets a local `editedAt` of `DateTime.now()` for immediate UI; the snapshot listener later replaces it with the server timestamp. Cosmetic only.
- **Storage upload testability**: `uploadChatImage`/`uploadPostImage` hit real `FirebaseStorage`, which fake_cloud_firestore doesn't cover; tests assert the message/URL contract rather than faking the upload (consistent with the existing `uploadPostImage`, which is likewise not unit-tested).
- **Fullscreen viewer** is a minimal `InteractiveViewer` in a dialog — not a gallery/zoom-pan-share surface (YAGNI).

## Definition of done

- Both features implemented behind the author-gated menu (edit) and the attach button (chat).
- `flutter analyze` clean; full suite green (existing 333 + new tests).
- QA_AUDIT_REPORT.md M-7 rows + Remediation Roadmap items 27/28 marked done.
- No rules/Storage/Functions deploy required; ships with the next app build.
