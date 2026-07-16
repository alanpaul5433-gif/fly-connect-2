import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/core/constants/app_routes.dart';
import 'package:flyconnect/core/services/notification_service.dart';

void main() {
  group('resolveRouteFromPayload', () {
    test('message with chatId → /conversation/{chatId}', () {
      final r = resolveRouteFromPayload({'type': 'message', 'chatId': 'c1'});
      expect(r, '${AppRoutes.conversation}/c1');
    });

    test('message without chatId falls back to /chat', () {
      expect(resolveRouteFromPayload({'type': 'message'}), AppRoutes.chat);
    });

    test('match → /match', () {
      expect(resolveRouteFromPayload({'type': 'match'}), AppRoutes.match);
      expect(
          resolveRouteFromPayload({'type': 'new_match'}), AppRoutes.match);
    });

    test('post_like / post_comment → /posts/{postId}', () {
      expect(
          resolveRouteFromPayload({'type': 'post_like', 'postId': 'p1'}),
          '${AppRoutes.postDetails}/p1');
      expect(
          resolveRouteFromPayload({'type': 'post_comment', 'postId': 'p2'}),
          '${AppRoutes.postDetails}/p2');
    });

    test('event → /events/{eventId}', () {
      expect(
          resolveRouteFromPayload({'type': 'event', 'eventId': 'e1'}),
          '${AppRoutes.eventDetails}/e1');
    });

    test('group → /groups/{groupId}', () {
      expect(
          resolveRouteFromPayload({'type': 'group', 'groupId': 'g1'}),
          '${AppRoutes.groupDetails}/g1');
    });

    test('promotion / new_promotion → /promotions/{promotionId}', () {
      expect(
          resolveRouteFromPayload({'type': 'promotion', 'promotionId': 'promo-1'}),
          '/promotions/promo-1');
      expect(
          resolveRouteFromPayload({'type': 'new_promotion', 'promotionId': 'promo-2'}),
          '/promotions/promo-2');
    });

    test('promotion without promotionId falls back to /offers', () {
      expect(resolveRouteFromPayload({'type': 'promotion'}), AppRoutes.offers);
    });

    test('follow → /users/{userId}', () {
      expect(
          resolveRouteFromPayload({'type': 'follow', 'userId': 'u1'}),
          '${AppRoutes.userProfile}/u1');
    });

    test('safe_check → /nearby', () {
      expect(resolveRouteFromPayload({'type': 'safe_check'}),
          AppRoutes.nearby);
      expect(resolveRouteFromPayload({'type': 'safecheck'}),
          AppRoutes.nearby);
    });

    test('unknown type falls back to /notifications', () {
      expect(resolveRouteFromPayload({'type': 'asteroid_impact'}),
          AppRoutes.notifications);
      expect(resolveRouteFromPayload({}), AppRoutes.notifications);
    });

    test('type is case-insensitive and trims whitespace', () {
      expect(
          resolveRouteFromPayload(
              {'type': '  MESSAGE ', 'chatId': 'cX'}),
          '${AppRoutes.conversation}/cX');
    });

    test('empty id strings are treated as missing', () {
      expect(resolveRouteFromPayload({'type': 'event', 'eventId': '   '}),
          AppRoutes.events);
    });

    test('non-string id values get .toString()ed', () {
      // FCM data is technically Map<String, String>, but mock harnesses
      // and tests sometimes pass through int ids.
      expect(
          resolveRouteFromPayload({'type': 'post', 'postId': 42}),
          '${AppRoutes.postDetails}/42');
    });
  });
}
