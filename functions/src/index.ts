// C-3: notification producers + push fan-out. See
// docs/superpowers/specs/2026-07-15-notification-producer-design.md.
export { onPostLikeCreated } from './producers/likes';
export { onPostCommentCreated } from './producers/comments';
export { onFollowerCreated } from './producers/follows';
export { onMatchUpdated } from './producers/matches';
export { onEventRsvpCreated } from './producers/rsvps';
export { onChatMessageCreated } from './producers/messages';
export { onPromotionApproved, onEventApproved, onGroupCreated } from './producers/businessContent';
export { onNotificationCreated } from './pushFanout';
// H20: daily follower-count snapshots so analytics can show real growth.
export { snapshotBusinessStats } from './dailyStats';
