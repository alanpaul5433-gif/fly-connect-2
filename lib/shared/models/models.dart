import 'package:cloud_firestore/cloud_firestore.dart';

// Models — Firestore-ready with fromFirestore/toFirestore methods

// ─── User Model ──────────────────────────────────────────────
class UserModel {
  final String uid;
  final String name;
  final String email;
  final String? phone;
  final String? photoUrl;
  final String? bio;
  final String? airline;
  final String? airport;
  final String? position;
  final String? city;
  final String? state;
  final List<String> hobbies;
  final List<String> passportStamps;
  final List<String> travelHistory;
  final String matchType;
  final int followerCount;
  final int followingCount;
  final int postCount;
  final String? fcmToken;
  final String role;
  final bool isVerified;
  final bool isBanned;
  final DateTime createdAt;
  final DateTime? lastSeen;

  const UserModel({
    required this.uid, required this.name, required this.email,
    this.phone, this.photoUrl, this.bio, this.airline, this.airport,
    this.position, this.city, this.state,
    this.hobbies = const [], this.passportStamps = const [],
    this.travelHistory = const [], this.matchType = 'all',
    this.followerCount = 0, this.followingCount = 0, this.postCount = 0,
    this.fcmToken, this.role = 'user', this.isVerified = false,
    this.isBanned = false, required this.createdAt, this.lastSeen,
  });

  factory UserModel.fromMap(Map<String, dynamic> d, String id) => UserModel(
    uid: id, name: d['name'] ?? '', email: d['email'] ?? '',
    phone: d['phone'], photoUrl: d['photoUrl'], bio: d['bio'],
    airline: d['airline'], airport: d['airport'], position: d['position'],
    city: d['city'], state: d['state'],
    hobbies: List<String>.from(d['hobbies'] ?? []),
    passportStamps: List<String>.from(d['passportStamps'] ?? []),
    travelHistory: List<String>.from(d['travelHistory'] ?? []),
    matchType: d['matchType'] ?? 'all',
    followerCount: d['followerCount'] ?? 0,
    followingCount: d['followingCount'] ?? 0,
    postCount: d['postCount'] ?? 0,
    fcmToken: d['fcmToken'], role: d['role'] ?? 'user',
    isVerified: d['isVerified'] ?? false, isBanned: d['isBanned'] ?? false,
    createdAt: d['createdAt'] is DateTime ? d['createdAt'] : DateTime.now(),
    lastSeen: d['lastSeen'] is DateTime ? d['lastSeen'] : null,
  );

  Map<String, dynamic> toMap() => {
    'name': name, 'email': email, 'phone': phone, 'photoUrl': photoUrl,
    'bio': bio, 'airline': airline, 'airport': airport, 'position': position,
    'city': city, 'state': state, 'hobbies': hobbies,
    'passportStamps': passportStamps, 'travelHistory': travelHistory,
    'matchType': matchType, 'followerCount': followerCount,
    'followingCount': followingCount, 'postCount': postCount,
    'fcmToken': fcmToken, 'role': role, 'isVerified': isVerified,
    'isBanned': isBanned, 'createdAt': createdAt, 'lastSeen': lastSeen,
  };

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['createdAt'] is Timestamp) d['createdAt'] = (d['createdAt'] as Timestamp).toDate();
    if (d['lastSeen'] is Timestamp) d['lastSeen'] = (d['lastSeen'] as Timestamp).toDate();
    return UserModel.fromMap(d, doc.id);
  }

  Map<String, dynamic> toFirestore() => toMap();

  UserModel copyWith({
    String? name, String? photoUrl, String? bio, String? airline,
    String? airport, String? position, String? city, String? state,
    List<String>? hobbies, List<String>? passportStamps,
    List<String>? travelHistory, String? matchType, String? fcmToken,
    int? followerCount, int? followingCount, int? postCount,
  }) => UserModel(
    uid: uid, email: email, createdAt: createdAt, phone: phone,
    name: name ?? this.name, photoUrl: photoUrl ?? this.photoUrl,
    bio: bio ?? this.bio, airline: airline ?? this.airline,
    airport: airport ?? this.airport, position: position ?? this.position,
    city: city ?? this.city, state: state ?? this.state,
    hobbies: hobbies ?? this.hobbies,
    passportStamps: passportStamps ?? this.passportStamps,
    travelHistory: travelHistory ?? this.travelHistory,
    matchType: matchType ?? this.matchType,
    fcmToken: fcmToken ?? this.fcmToken,
    followerCount: followerCount ?? this.followerCount,
    followingCount: followingCount ?? this.followingCount,
    postCount: postCount ?? this.postCount,
    role: role, isVerified: isVerified, isBanned: isBanned,
  );
}

// ─── Post Model ──────────────────────────────────────────────
class PostModel {
  final String id;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final List<String> mediaUrls;
  final String mediaType;
  final String? thumbnailUrl; // poster frame for video posts
  final double? aspectRatio;  // width/height of the video, for layout
  final int? durationMs;      // video length in milliseconds
  final String caption;
  final String? location;
  final int likeCount;
  final int commentCount;
  final bool isReported;
  final int reportCount;
  final String? groupId;
  final DateTime createdAt;

  const PostModel({
    required this.id, required this.authorId, required this.authorName,
    this.authorPhotoUrl, this.mediaUrls = const [], this.mediaType = 'text',
    this.thumbnailUrl, this.aspectRatio, this.durationMs,
    this.caption = '', this.location, this.likeCount = 0,
    this.commentCount = 0, this.isReported = false, this.reportCount = 0,
    this.groupId, required this.createdAt,
  });

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

  Map<String, dynamic> toFirestore() => {
    'authorId': authorId, 'authorName': authorName, 'authorPhotoUrl': authorPhotoUrl,
    'mediaUrls': mediaUrls, 'mediaType': mediaType,
    'thumbnailUrl': thumbnailUrl, 'aspectRatio': aspectRatio, 'durationMs': durationMs,
    'caption': caption,
    'location': location, 'likeCount': likeCount, 'commentCount': commentCount,
    'isReported': isReported, 'reportCount': reportCount, 'groupId': groupId,
    'createdAt': createdAt,
  };
}

// ─── Comment Model ───────────────────────────────────────────
class CommentModel {
  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String text;
  final int likeCount;
  final DateTime createdAt;

  const CommentModel({
    required this.id, required this.postId, required this.authorId,
    required this.authorName, this.authorPhotoUrl, required this.text,
    this.likeCount = 0, required this.createdAt,
  });

  factory CommentModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['createdAt'] is Timestamp) d['createdAt'] = (d['createdAt'] as Timestamp).toDate();
    return CommentModel(
      id: doc.id,
      postId: d['postId'] ?? doc.reference.parent.parent?.id ?? '',
      authorId: d['authorId'] ?? '',
      authorName: d['authorName'] ?? '',
      authorPhotoUrl: d['authorPhotoUrl'],
      text: d['text'] ?? '',
      likeCount: d['likeCount'] ?? 0,
      createdAt: d['createdAt'] is DateTime ? d['createdAt'] : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'postId': postId, 'authorId': authorId, 'authorName': authorName,
    'authorPhotoUrl': authorPhotoUrl, 'text': text, 'likeCount': likeCount,
    'createdAt': createdAt,
  };
}

// ─── Chat Model ──────────────────────────────────────────────
class ChatModel {
  final String id;
  final String type;
  final List<String> participants;
  final String? groupName;
  final String? groupPhotoUrl;
  final String? lastMessage;
  final String? lastMessageSenderId;
  final DateTime? lastMessageAt;
  final String createdBy;
  final Map<String, int> unreadCount;
  final DateTime createdAt;

  const ChatModel({
    required this.id, required this.type, required this.participants,
    this.groupName, this.groupPhotoUrl, this.lastMessage,
    this.lastMessageSenderId, this.lastMessageAt, required this.createdBy,
    this.unreadCount = const {}, required this.createdAt,
  });

  factory ChatModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['lastMessageAt'] is Timestamp) d['lastMessageAt'] = (d['lastMessageAt'] as Timestamp).toDate();
    if (d['createdAt'] is Timestamp) d['createdAt'] = (d['createdAt'] as Timestamp).toDate();
    return ChatModel(
      id: doc.id,
      type: d['type'] ?? '',
      participants: List<String>.from(d['participants'] ?? []),
      groupName: d['groupName'],
      groupPhotoUrl: d['groupPhotoUrl'],
      lastMessage: d['lastMessage'],
      lastMessageSenderId: d['lastMessageSenderId'],
      lastMessageAt: d['lastMessageAt'] is DateTime ? d['lastMessageAt'] : null,
      createdBy: d['createdBy'] ?? '',
      unreadCount: Map<String, int>.from(d['unreadCount'] ?? {}),
      createdAt: d['createdAt'] is DateTime ? d['createdAt'] : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'type': type, 'participants': participants, 'groupName': groupName,
    'groupPhotoUrl': groupPhotoUrl, 'lastMessage': lastMessage,
    'lastMessageSenderId': lastMessageSenderId, 'lastMessageAt': lastMessageAt,
    'createdBy': createdBy, 'unreadCount': unreadCount, 'createdAt': createdAt,
  };
}

// ─── Message Model ───────────────────────────────────────────
class MessageModel {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String text;
  final String? mediaUrl;
  final String mediaType;
  final List<String> readBy;
  final DateTime createdAt;

  const MessageModel({
    required this.id, required this.chatId, required this.senderId,
    required this.senderName, this.senderPhotoUrl, required this.text,
    this.mediaUrl, this.mediaType = 'text', this.readBy = const [],
    required this.createdAt,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['createdAt'] is Timestamp) d['createdAt'] = (d['createdAt'] as Timestamp).toDate();
    return MessageModel(
      id: doc.id,
      chatId: d['chatId'] ?? '',
      senderId: d['senderId'] ?? '',
      senderName: d['senderName'] ?? '',
      senderPhotoUrl: d['senderPhotoUrl'],
      text: d['text'] ?? '',
      mediaUrl: d['mediaUrl'],
      mediaType: d['mediaType'] ?? 'text',
      readBy: List<String>.from(d['readBy'] ?? []),
      createdAt: d['createdAt'] is DateTime ? d['createdAt'] : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'chatId': chatId, 'senderId': senderId, 'senderName': senderName,
    'senderPhotoUrl': senderPhotoUrl, 'text': text, 'mediaUrl': mediaUrl,
    'mediaType': mediaType, 'readBy': readBy, 'createdAt': createdAt,
  };
}

// ─── Event Model ─────────────────────────────────────────────
class EventModel {
  final String id;
  final String title;
  final String description;
  final String? imageUrl;
  final String location;
  final DateTime date;
  final String time;
  final String createdBy;
  final String? groupId;
  final List<String> rsvpList;
  final int rsvpCount;
  final bool isApproved;
  final bool isFeatured;
  final List<String> requirements;
  final DateTime createdAt;

  const EventModel({
    required this.id, required this.title, required this.description,
    this.imageUrl, required this.location, required this.date,
    required this.time, required this.createdBy, this.groupId,
    this.rsvpList = const [], this.rsvpCount = 0, this.isApproved = false,
    this.isFeatured = false, this.requirements = const [],
    required this.createdAt,
  });

  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['date'] is Timestamp) d['date'] = (d['date'] as Timestamp).toDate();
    if (d['createdAt'] is Timestamp) d['createdAt'] = (d['createdAt'] as Timestamp).toDate();
    return EventModel(
      id: doc.id,
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      imageUrl: d['imageUrl'],
      location: d['location'] ?? '',
      date: d['date'] is DateTime ? d['date'] : DateTime.now(),
      time: d['time'] ?? '',
      createdBy: d['createdBy'] ?? '',
      groupId: d['groupId'],
      rsvpList: List<String>.from(d['rsvpList'] ?? []),
      rsvpCount: d['rsvpCount'] ?? 0,
      isApproved: d['isApproved'] ?? false,
      isFeatured: d['isFeatured'] ?? false,
      requirements: List<String>.from(d['requirements'] ?? []),
      createdAt: d['createdAt'] is DateTime ? d['createdAt'] : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'title': title, 'description': description, 'imageUrl': imageUrl,
    'location': location, 'date': date, 'time': time, 'createdBy': createdBy,
    'groupId': groupId, 'rsvpList': rsvpList, 'rsvpCount': rsvpCount,
    'isApproved': isApproved, 'isFeatured': isFeatured,
    'requirements': requirements, 'createdAt': createdAt,
  };
}

// ─── Group Model ─────────────────────────────────────────────
class GroupModel {
  final String id;
  final String name;
  final String description;
  final String? imageUrl;
  final String createdBy;
  final List<String> members;
  final List<String> admins;
  final int memberCount;
  final bool isPublic;
  final List<String> tags;
  final String? location;
  final bool isPinned;
  final String? chatId;
  final DateTime createdAt;

  const GroupModel({
    required this.id, required this.name, required this.description,
    this.imageUrl, required this.createdBy, this.members = const [],
    this.admins = const [], this.memberCount = 0, this.isPublic = true,
    this.tags = const [], this.location, this.isPinned = false,
    this.chatId, required this.createdAt,
  });

  factory GroupModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['createdAt'] is Timestamp) d['createdAt'] = (d['createdAt'] as Timestamp).toDate();
    return GroupModel(
      id: doc.id,
      name: d['name'] ?? '',
      description: d['description'] ?? '',
      imageUrl: d['imageUrl'],
      createdBy: d['createdBy'] ?? '',
      members: List<String>.from(d['members'] ?? []),
      admins: List<String>.from(d['admins'] ?? []),
      memberCount: d['memberCount'] ?? 0,
      isPublic: d['isPublic'] ?? true,
      tags: List<String>.from(d['tags'] ?? []),
      location: d['location'],
      isPinned: d['isPinned'] ?? false,
      chatId: d['chatId'],
      createdAt: d['createdAt'] is DateTime ? d['createdAt'] : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name, 'description': description, 'imageUrl': imageUrl,
    'createdBy': createdBy, 'members': members, 'admins': admins,
    'memberCount': memberCount, 'isPublic': isPublic, 'tags': tags,
    'location': location, 'isPinned': isPinned, 'chatId': chatId,
    'createdAt': createdAt,
  };
}

// ─── Match Model ─────────────────────────────────────────────
class MatchModel {
  final String id;
  final String userA;
  final String userB;
  final String status;
  final String matchType;
  final DateTime likedAt;
  final DateTime? matchedAt;
  final String? chatId;

  const MatchModel({
    required this.id, required this.userA, required this.userB,
    required this.status, required this.matchType, required this.likedAt,
    this.matchedAt, this.chatId,
  });

  factory MatchModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['likedAt'] is Timestamp) d['likedAt'] = (d['likedAt'] as Timestamp).toDate();
    if (d['matchedAt'] is Timestamp) d['matchedAt'] = (d['matchedAt'] as Timestamp).toDate();
    return MatchModel(
      id: doc.id,
      userA: d['userA'] ?? '',
      userB: d['userB'] ?? '',
      status: d['status'] ?? '',
      matchType: d['matchType'] ?? '',
      likedAt: d['likedAt'] is DateTime ? d['likedAt'] : DateTime.now(),
      matchedAt: d['matchedAt'] is DateTime ? d['matchedAt'] : null,
      chatId: d['chatId'],
    );
  }

  Map<String, dynamic> toFirestore() => {
    'userA': userA, 'userB': userB, 'status': status, 'matchType': matchType,
    'likedAt': likedAt, 'matchedAt': matchedAt, 'chatId': chatId,
  };
}

// ─── Notification Model ──────────────────────────────────────
class NotificationModel {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final String? imageUrl;
  final String? deepLink;
  final bool isRead;
  final DateTime createdAt;

  const NotificationModel({
    required this.id, required this.userId, required this.type,
    required this.title, required this.body, this.imageUrl, this.deepLink,
    this.isRead = false, required this.createdAt,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['createdAt'] is Timestamp) d['createdAt'] = (d['createdAt'] as Timestamp).toDate();
    return NotificationModel(
      id: doc.id,
      userId: d['userId'] ?? '',
      type: d['type'] ?? '',
      title: d['title'] ?? '',
      body: d['body'] ?? '',
      imageUrl: d['imageUrl'],
      deepLink: d['deepLink'],
      isRead: d['isRead'] ?? false,
      createdAt: d['createdAt'] is DateTime ? d['createdAt'] : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'userId': userId, 'type': type, 'title': title, 'body': body,
    'imageUrl': imageUrl, 'deepLink': deepLink, 'isRead': isRead,
    'createdAt': createdAt,
  };
}

// ─── Promotion Model ─────────────────────────────────────────
class PromotionModel {
  final String id;
  final String businessId;
  final String businessName;
  final String title;
  final String description;
  final String? imageUrl;
  final int discountPercent;
  final DateTime validFrom;
  final DateTime validTo;
  final int maxRedemptions;
  final int currentRedemptions;
  final int views;
  final int saves;
  final bool isActive;
  final bool isApproved;

  const PromotionModel({
    required this.id, required this.businessId, required this.businessName,
    required this.title, required this.description, this.imageUrl,
    required this.discountPercent, required this.validFrom, required this.validTo,
    required this.maxRedemptions, this.currentRedemptions = 0,
    this.views = 0, this.saves = 0, this.isActive = true,
    this.isApproved = false,
  });

  factory PromotionModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['validFrom'] is Timestamp) d['validFrom'] = (d['validFrom'] as Timestamp).toDate();
    if (d['validTo'] is Timestamp) d['validTo'] = (d['validTo'] as Timestamp).toDate();
    return PromotionModel(
      id: doc.id,
      businessId: d['businessId'] ?? '',
      businessName: d['businessName'] ?? '',
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      imageUrl: d['imageUrl'],
      discountPercent: d['discountPercent'] ?? 0,
      validFrom: d['validFrom'] is DateTime ? d['validFrom'] : DateTime.now(),
      validTo: d['validTo'] is DateTime ? d['validTo'] : DateTime.now(),
      maxRedemptions: d['maxRedemptions'] ?? 0,
      currentRedemptions: d['currentRedemptions'] ?? 0,
      views: d['views'] ?? 0,
      saves: d['saves'] ?? 0,
      isActive: d['isActive'] ?? true,
      isApproved: d['isApproved'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'businessId': businessId, 'businessName': businessName, 'title': title,
    'description': description, 'imageUrl': imageUrl,
    'discountPercent': discountPercent, 'validFrom': validFrom,
    'validTo': validTo, 'maxRedemptions': maxRedemptions,
    'currentRedemptions': currentRedemptions, 'views': views, 'saves': saves,
    'isActive': isActive,
    'isApproved': isApproved,
  };
}

// ─── Trip Model ──────────────────────────────────────────────
class TripModel {
  final String id;
  final String userId;
  final String destination;
  final String countryCode;
  final String? description;
  final List<String> photoUrls;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime createdAt;

  const TripModel({
    required this.id, required this.userId, required this.destination,
    required this.countryCode, this.description, this.photoUrls = const [],
    required this.startDate, this.endDate, required this.createdAt,
  });

  factory TripModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['startDate'] is Timestamp) d['startDate'] = (d['startDate'] as Timestamp).toDate();
    if (d['endDate'] is Timestamp) d['endDate'] = (d['endDate'] as Timestamp).toDate();
    if (d['createdAt'] is Timestamp) d['createdAt'] = (d['createdAt'] as Timestamp).toDate();
    return TripModel(
      id: doc.id,
      userId: d['userId'] ?? '',
      destination: d['destination'] ?? '',
      countryCode: d['countryCode'] ?? '',
      description: d['description'],
      photoUrls: List<String>.from(d['photoUrls'] ?? []),
      startDate: d['startDate'] is DateTime ? d['startDate'] : DateTime.now(),
      endDate: d['endDate'] is DateTime ? d['endDate'] : null,
      createdAt: d['createdAt'] is DateTime ? d['createdAt'] : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'userId': userId, 'destination': destination, 'countryCode': countryCode,
    'description': description, 'photoUrls': photoUrls, 'startDate': startDate,
    'endDate': endDate, 'createdAt': createdAt,
  };
}

// ─── SafeCheck Model ────────────────────────────────────────
class SafeCheckModel {
  final String id;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final String status; // 'safe', 'unsure', 'need_help'
  final String? message;
  final String city;
  final double? lat;
  final double? lng;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const SafeCheckModel({
    required this.id, required this.userId, required this.userName,
    this.userPhotoUrl, required this.status, this.message,
    required this.city, this.lat, this.lng,
    required this.createdAt, this.expiresAt,
  });

  bool get isActive => expiresAt == null || expiresAt!.isAfter(DateTime.now());

  factory SafeCheckModel.fromMap(Map<String, dynamic> d, String id) => SafeCheckModel(
    id: id, userId: d['userId'] ?? '', userName: d['userName'] ?? '',
    userPhotoUrl: d['userPhotoUrl'], status: d['status'] ?? 'safe',
    message: d['message'], city: d['city'] ?? '',
    lat: (d['lat'] as num?)?.toDouble(), lng: (d['lng'] as num?)?.toDouble(),
    createdAt: d['createdAt'] is DateTime ? d['createdAt'] : DateTime.now(),
    expiresAt: d['expiresAt'] is DateTime ? d['expiresAt'] : null,
  );

  Map<String, dynamic> toMap() => {
    'userId': userId, 'userName': userName, 'userPhotoUrl': userPhotoUrl,
    'status': status, 'message': message, 'city': city,
    'lat': lat, 'lng': lng, 'createdAt': createdAt, 'expiresAt': expiresAt,
  };

  factory SafeCheckModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['createdAt'] is Timestamp) d['createdAt'] = (d['createdAt'] as Timestamp).toDate();
    if (d['expiresAt'] is Timestamp) d['expiresAt'] = (d['expiresAt'] as Timestamp).toDate();
    return SafeCheckModel.fromMap(d, doc.id);
  }

  Map<String, dynamic> toFirestore() => toMap();
}
