import 'package:flyconnect/shared/models/models.dart';

/// Thin fixture factories for GroupModel/EventModel/UserModel — sensible
/// defaults with named overrides, no builder pattern. Promoted to shared
/// scope because several test files construct the same 12-15-field models;
/// past 2-3 files, copy-paste drift (e.g. inconsistent chatEnabled defaults)
/// outweighs keeping every test file fully self-contained.
GroupModel buildGroup({
  String id = 'grp-1',
  String name = 'Test Group',
  String description = 'A test group',
  String createdBy = 'biz-1',
  List<String> members = const [],
  List<String> admins = const [],
  int memberCount = 0,
  bool chatEnabled = true,
}) =>
    GroupModel(
      id: id,
      name: name,
      description: description,
      createdBy: createdBy,
      members: members,
      admins: admins,
      memberCount: memberCount,
      chatEnabled: chatEnabled,
      createdAt: DateTime(2026, 1, 1),
    );

EventModel buildEvent({
  String id = 'evt-1',
  String title = 'Test Event',
  String description = 'A test event',
  String location = 'Test Lounge',
  String time = '6:00 PM',
  String createdBy = 'biz-1',
  List<String> rsvpList = const [],
  int rsvpCount = 0,
}) =>
    EventModel(
      id: id,
      title: title,
      description: description,
      location: location,
      date: DateTime(2026, 6, 1),
      time: time,
      createdBy: createdBy,
      rsvpList: rsvpList,
      rsvpCount: rsvpCount,
      createdAt: DateTime(2026, 1, 1),
    );

UserModel buildUser({
  String uid = 'user-1',
  String name = 'Test User',
  String role = 'user',
  String? city,
}) =>
    UserModel(
      uid: uid,
      name: name,
      email: '$uid@example.com',
      role: role,
      city: city,
      createdAt: DateTime(2026, 1, 1),
    );

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
