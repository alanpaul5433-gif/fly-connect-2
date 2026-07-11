class AppRoutes {
  // Auth
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const signup = '/signup';
  static const otp = '/otp';
  static const forgotPassword = '/forgot-password';

  // Main tabs
  static const home = '/home';
  static const events = '/events';
  static const match = '/match';
  static const chat = '/chat';
  static const profile = '/profile';

  // Standalone screens
  static const createGroup   = '/create-group';
  static const createPost    = '/create-post';
  static const editProfile   = '/edit-profile';
  static const editProfileDetails = '/edit-profile/details';
  static const nearby        = '/nearby';
  static const settings      = '/settings';
  static const notifications = '/notifications';
  static const search        = '/search';
  static const trips         = '/trips';
  static const groupsList    = '/groups-list';
  static const matchPreferences = '/match-preferences';
  static const safeCheckHistory = '/safe-check-history';
  static const offers           = '/offers';       // crew-facing promotions browser

  // Admin Dashboard
  static const adminDashboard     = '/admin/dashboard';
  static const adminUsers         = '/admin/users';
  static const adminContent       = '/admin/content';
  static const adminSafeCheck     = '/admin/safecheck';
  static const adminNearby        = '/admin/nearby';
  static const adminEvents        = '/admin/events';
  static const adminAnalytics     = '/admin/analytics';
  static const adminNotifications = '/admin/notifications';
  static const adminReports      = '/admin/reports';
  static const adminPromotions   = '/admin/promotions';
  static const adminGdpr         = '/admin/gdpr';
  static const adminAudit        = '/admin/audit';
  static const adminBusinessVerify = '/admin/business-verify';

  // Deep-link capable
  static const userProfile   = '/users';         // /users/:userId
  static const conversation  = '/conversation';  // /conversation/:chatId
  static const groupDetails  = '/groups';        // /groups/:groupId
  static const postDetails   = '/posts';         // /posts/:postId
  static const passport      = '/passport';      // /passport/:userId
  static const eventDetails  = '/events';        // /events/:eventId
}
