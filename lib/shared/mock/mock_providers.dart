import 'package:flutter/material.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import 'mock_data.dart';

// ─── Mock User Provider ───────────────────────────────────────
class UserProvider extends ChangeNotifier {
  UserModel? _currentUser;
  final Set<String> _following = {'user_002', 'user_006'};

  UserModel? get currentUser => _currentUser;
  bool get loading => false;

  void updateAuth(AuthProvider auth) {
    _currentUser = auth.currentUser;
    notifyListeners();
  }

  Future<UserModel?> fetchUser(String uid) async {
    if (uid == 'mock_alex' || uid == 'user_001') return mockCurrentUser;
    if (uid == 'mock_biz1' || uid == 'biz_001') return mockBusinessUser;
    if (uid == 'mock_biz2' || uid == 'biz_002') return mockBusinessUser2;
    if (uid == 'mock_sarah' || uid == 'user_007') return mockCurrentUser2;
    return mockUsers.where((u) => u.uid == uid).firstOrNull;
  }

  Future<void> updateProfile(String uid, Map<String, dynamic> data) async {
    await Future.delayed(const Duration(milliseconds: 500));
    notifyListeners();
  }

  Future<void> followUser(String targetUid) async {
    _following.add(targetUid);
    notifyListeners();
  }

  Future<void> unfollowUser(String targetUid) async {
    _following.remove(targetUid);
    notifyListeners();
  }

  Future<bool> isFollowing(String targetUid) async => _following.contains(targetUid);
}

// ─── Mock Post Provider ───────────────────────────────────────
class PostProvider extends ChangeNotifier {
  final List<PostModel> _feed = List.from(mockPosts);
  final Set<String> _liked = {'post_003'};
  final Set<String> _saved = {};
  bool get loading => false;
  List<PostModel> get feed => _feed;

  void updateAuth(AuthProvider auth) {}
  void listenFeed() {}

  Future<void> likePost(String postId) async {
    _liked.add(postId);
    final i = _feed.indexWhere((p) => p.id == postId);
    if (i != -1) {
      _feed[i] = PostModel(
        id: _feed[i].id, authorId: _feed[i].authorId, authorName: _feed[i].authorName,
        authorPhotoUrl: _feed[i].authorPhotoUrl, caption: _feed[i].caption,
        mediaUrls: _feed[i].mediaUrls, mediaType: _feed[i].mediaType,
        location: _feed[i].location, likeCount: _feed[i].likeCount + 1,
        commentCount: _feed[i].commentCount, createdAt: _feed[i].createdAt);
    }
    notifyListeners();
  }

  Future<void> unlikePost(String postId) async {
    _liked.remove(postId);
    final i = _feed.indexWhere((p) => p.id == postId);
    if (i != -1) {
      _feed[i] = PostModel(
        id: _feed[i].id, authorId: _feed[i].authorId, authorName: _feed[i].authorName,
        authorPhotoUrl: _feed[i].authorPhotoUrl, caption: _feed[i].caption,
        mediaUrls: _feed[i].mediaUrls, mediaType: _feed[i].mediaType,
        location: _feed[i].location, likeCount: (_feed[i].likeCount - 1).clamp(0, 9999),
        commentCount: _feed[i].commentCount, createdAt: _feed[i].createdAt);
    }
    notifyListeners();
  }

  Future<bool> isLiked(String postId) async => _liked.contains(postId);
  Future<void> savePost(String postId) async { _saved.add(postId); notifyListeners(); }
  Future<void> unsavePost(String postId) async { _saved.remove(postId); notifyListeners(); }
  Future<bool> isSaved(String postId) async => _saved.contains(postId);

  Stream<List<CommentModel>> watchComments(String postId) => Stream.value([
    CommentModel(id: 'c1', postId: postId, authorId: 'user_002',
      authorName: 'Maria Chen', text: 'This is amazing! 🔥',
      createdAt: DateTime.now().subtract(const Duration(minutes: 30))),
    CommentModel(id: 'c2', postId: postId, authorId: 'user_003',
      authorName: 'James Wright', text: 'So inspiring! Congrats 🎉',
      createdAt: DateTime.now().subtract(const Duration(minutes: 15))),
  ]);

  Future<void> addComment(String postId, String text) async {}
  Future<void> reportPost(String postId) async {}

  Future<void> createPost({required String caption, List<String> mediaUrls = const [],
    String mediaType = 'text', String? location, String? groupId}) async {
    final post = PostModel(
      id: 'post_new_${DateTime.now().millisecondsSinceEpoch}',
      authorId: 'user_001', authorName: 'Alex Johnson',
      caption: caption, mediaUrls: mediaUrls, mediaType: mediaType,
      location: location, likeCount: 0, commentCount: 0, createdAt: DateTime.now());
    _feed.insert(0, post);
    notifyListeners();
  }
}

// ─── Mock Chat Provider ───────────────────────────────────────
class ChatProvider extends ChangeNotifier {
  final List<ChatModel> _chats = List.from(mockChats);
  List<ChatModel> get chats => _chats;

  void updateAuth(AuthProvider auth) {}

  Stream<List<MessageModel>> watchMessages(String chatId) =>
    Stream.value(mockMessages[chatId] ?? []);

  Future<void> sendMessage(String chatId, String text,
      {String? mediaUrl, String mediaType = 'text'}) async {
    final msg = MessageModel(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}', chatId: chatId,
      senderId: 'user_001', senderName: 'Alex Johnson', text: text,
      mediaType: mediaType, readBy: ['user_001'], createdAt: DateTime.now());
    mockMessages[chatId] = [...(mockMessages[chatId] ?? []), msg];
    final i = _chats.indexWhere((c) => c.id == chatId);
    if (i != -1) {
      final c = _chats[i];
      _chats[i] = ChatModel(id: c.id, type: c.type, participants: c.participants,
        groupName: c.groupName, lastMessage: text, lastMessageAt: DateTime.now(),
        unreadCount: c.unreadCount, createdBy: c.createdBy, createdAt: c.createdAt);
    }
    notifyListeners();
  }

  Future<void> markAsRead(String chatId) async {}

  Future<String> getOrCreateDm(String otherUid) async {
    final existing = _chats.where((c) =>
      c.type == 'dm' && c.participants.contains(otherUid)).firstOrNull;
    if (existing != null) return existing.id;
    final newId = 'chat_new_$otherUid';
    final other = mockUsers.where((u) => u.uid == otherUid).firstOrNull;
    _chats.add(ChatModel(id: newId, type: 'dm',
      participants: ['user_001', otherUid],
      participantNames: ChatModel.namesMap(
        meUid: 'user_001', meName: mockCurrentUser.name,
        otherUid: otherUid, otherName: other?.name),
      lastMessage: null, lastMessageAt: null, unreadCount: {},
      createdBy: 'user_001', createdAt: DateTime.now()));
    notifyListeners();
    return newId;
  }

  Future<void> setTyping(String chatId, bool isTyping) async {}
  Stream<Map<String, bool>> watchTyping(String chatId) => Stream.value({});
}

// ─── Mock Event Provider ──────────────────────────────────────
class EventProvider extends ChangeNotifier {
  final List<EventModel> _events = List.from(mockEvents);
  final Set<String> _rsvpd = {'evt_004'};
  List<EventModel> get events => _events;

  void updateAuth(AuthProvider auth) {}

  Future<void> toggleRsvp(String eventId) async {
    if (_rsvpd.contains(eventId)) { _rsvpd.remove(eventId); }
    else { _rsvpd.add(eventId); }
    notifyListeners();
  }

  Future<bool> hasRsvped(String eventId) async => _rsvpd.contains(eventId);
  bool isRsvpd(String eventId) => _rsvpd.contains(eventId);

  void addEvent(EventModel event) {
    _events.insert(0, event);
    notifyListeners();
  }
}

// ─── Mock Group Provider ──────────────────────────────────────
class GroupProvider extends ChangeNotifier {
  final List<GroupModel> _groups = List.from(mockGroups);
  final Set<String> _joined = {'grp_001', 'grp_002'};

  List<GroupModel> get groups => _groups;
  List<GroupModel> get myGroups => _groups.where((g) => _joined.contains(g.id)).toList();

  void updateAuth(AuthProvider auth) {}

  Future<GroupModel?> getGroup(String groupId) async =>
    _groups.where((g) => g.id == groupId).firstOrNull;

  Future<void> joinGroup(String groupId) async {
    _joined.add(groupId);
    notifyListeners();
  }

  Future<void> leaveGroup(String groupId) async {
    _joined.remove(groupId);
    notifyListeners();
  }

  bool isMember(String groupId) => _joined.contains(groupId);

  void createGroup(GroupModel group) {
    _groups.insert(0, group);
    _joined.add(group.id);
    notifyListeners();
  }
}

// ─── Mock Match Provider ──────────────────────────────────────
class MatchProvider extends ChangeNotifier {
  final List<UserModel> _candidates = List.from(mockUsers);
  final List<MatchModel> _matches = [];
  bool get loading => false;
  List<UserModel> get candidates => _candidates;
  List<MatchModel> get matches => _matches;

  void updateAuth(AuthProvider auth) {}

  Future<void> loadCandidates() async {
    _candidates..clear()..addAll(mockUsers);
    notifyListeners();
  }

  /// Returns whether the like produced a mutual match — see the real
  /// MatchProvider.likeUser. Keyed off the target uid rather than the wall
  /// clock so the same card gives the same answer every run.
  Future<bool> likeUser(String targetUid, String matchType) async {
    _candidates.removeWhere((u) => u.uid == targetUid);
    final matched = mockUsers.where((u) => u.uid == targetUid).firstOrNull;
    final isMatch = matched != null && targetUid.hashCode.isEven;
    if (isMatch) {
      _matches.add(MatchModel(
        id: 'match_$targetUid', userA: 'user_001', userB: targetUid,
        status: 'matched', matchType: matchType,
        likedAt: DateTime.now(), matchedAt: DateTime.now()));
    }
    notifyListeners();
    return isMatch;
  }

  Future<void> passUser(String targetUid) async {
    _candidates.removeWhere((u) => u.uid == targetUid);
    notifyListeners();
  }
}

// ─── Mock Notification Provider ───────────────────────────────
class NotificationProvider extends ChangeNotifier {
  final List<NotificationModel> _notifications = List.from(mockNotifications);

  List<NotificationModel> get notifications => _notifications;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  void updateAuth(AuthProvider auth) {}

  Stream<List<NotificationModel>> watchNotifications() => Stream.value(_notifications);

  Future<void> markAsRead(String id) async {
    final i = _notifications.indexWhere((n) => n.id == id);
    if (i != -1) {
      final n = _notifications[i];
      _notifications[i] = NotificationModel(id: n.id, userId: n.userId,
        type: n.type, title: n.title, body: n.body,
        imageUrl: n.imageUrl, deepLink: n.deepLink,
        isRead: true, createdAt: n.createdAt);
      notifyListeners();
    }
  }

  Future<void> markAllAsRead() async {
    for (int i = 0; i < _notifications.length; i++) {
      final n = _notifications[i];
      _notifications[i] = NotificationModel(id: n.id, userId: n.userId,
        type: n.type, title: n.title, body: n.body,
        imageUrl: n.imageUrl, deepLink: n.deepLink,
        isRead: true, createdAt: n.createdAt);
    }
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }
}

// ─── Mock Trip Provider ───────────────────────────────────────
class TripProvider extends ChangeNotifier {
  final List<TripModel> _trips = List.from(mockTrips);
  List<TripModel> get trips => _trips;

  void updateAuth(AuthProvider auth) {}

  Future<void> addTrip(TripModel trip) async {
    _trips.insert(0, trip);
    notifyListeners();
  }

  Future<void> deleteTrip(String tripId) async {
    _trips.removeWhere((t) => t.id == tripId);
    notifyListeners();
  }
}

// ─── Mock Promotion Provider ──────────────────────────────────
class PromotionProvider extends ChangeNotifier {
  final List<PromotionModel> _promotions = List.from(mockPromotions);
  List<PromotionModel> get promotions => _promotions;
  List<PromotionModel> get activePromotions =>
      _promotions.where((p) => p.isActive && p.isApproved).toList();
  List<PromotionModel> get expiredPromotions => _promotions.where((p) => !p.isActive).toList();
  void updateAuth(AuthProvider auth) {}

  void addPromotion(PromotionModel promo) {
    _promotions.insert(0, promo);
    notifyListeners();
  }
}

// ─── Mock Search Provider ─────────────────────────────────────
class SearchProvider extends ChangeNotifier {
  List<UserModel> _userResults = [];
  List<EventModel> _eventResults = [];
  List<GroupModel> _groupResults = [];
  bool _loading = false;
  String _query = '';

  List<UserModel> get userResults => _userResults;
  List<EventModel> get eventResults => _eventResults;
  List<GroupModel> get groupResults => _groupResults;
  bool get loading => _loading;
  String get query => _query;

  void updateAuth(AuthProvider auth) {}

  Future<void> search(String q) async {
    if (q.isEmpty) { clear(); return; }
    _query = q; _loading = true; notifyListeners();
    await Future.delayed(const Duration(milliseconds: 400));
    final lower = q.toLowerCase();
    _userResults = [...mockUsers, mockCurrentUser]
      .where((u) => u.name.toLowerCase().contains(lower) ||
        (u.airline?.toLowerCase().contains(lower) ?? false)).toList();
    _eventResults = mockEvents
      .where((e) => e.title.toLowerCase().contains(lower) ||
        e.location.toLowerCase().contains(lower)).toList();
    _groupResults = mockGroups
      .where((g) => g.name.toLowerCase().contains(lower) ||
        g.tags.any((t) => t.toLowerCase().contains(lower))).toList();
    _loading = false; notifyListeners();
  }

  void clear() {
    _query = ''; _userResults = []; _eventResults = []; _groupResults = [];
    notifyListeners();
  }
}

// ─── Mock SafeCheck Provider ─────────────────────────────────
class SafeCheckProvider extends ChangeNotifier {
  final List<SafeCheckModel> _checkIns = List.from(mockSafeChecks);
  SafeCheckModel? _myLatestCheckIn;
  bool _loading = false;

  List<SafeCheckModel> get checkIns => _checkIns;
  SafeCheckModel? get myLatestCheckIn => _myLatestCheckIn;
  bool get loading => _loading;
  List<SafeCheckModel> get activeCheckIns => _checkIns.where((c) => c.isActive).toList();

  void updateAuth(AuthProvider auth) {}

  List<SafeCheckModel> nearbyCheckIns(String city) =>
    activeCheckIns.where((c) => c.city.toLowerCase() == city.toLowerCase()).toList();

  SafeCheckModel? latestForUser(String userId) {
    final userCheckIns = activeCheckIns.where((c) => c.userId == userId).toList();
    if (userCheckIns.isEmpty) return null;
    userCheckIns.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return userCheckIns.first;
  }

  Future<void> checkIn({
    required String status, String? message, required String city,
    double? lat, double? lng, required String userId,
    required String userName, String? userPhotoUrl,
  }) async {
    _loading = true; notifyListeners();
    await Future.delayed(const Duration(milliseconds: 500));
    final now = DateTime.now();
    final checkIn = SafeCheckModel(
      id: 'sc_${now.millisecondsSinceEpoch}', userId: userId,
      userName: userName, userPhotoUrl: userPhotoUrl,
      status: status, message: message, city: city, lat: lat, lng: lng,
      createdAt: now, expiresAt: now.add(const Duration(hours: 24)));
    _checkIns.removeWhere((c) => c.userId == userId && c.isActive);
    _checkIns.insert(0, checkIn);
    _myLatestCheckIn = checkIn;
    _loading = false; notifyListeners();
  }

  void clearMyCheckIn(String userId) {
    _checkIns.removeWhere((c) => c.userId == userId && c.isActive);
    _myLatestCheckIn = null;
    notifyListeners();
  }
}
