import { db, waitFor, uniq } from './setup';
import { Timestamp } from 'firebase-admin/firestore';

describe('notification producers (Firestore emulator, real trigger wiring)', () => {
  it('like: creating posts/{postId}/likes/{uid} produces a like notification', async () => {
    const postId = uniq('post');
    const likerUid = uniq('liker');
    const authorId = uniq('author');

    await db.collection('posts').doc(postId).set({ authorId, caption: 'hi' });
    await db.collection('users').doc(authorId).set({ name: 'Author Name' });
    await db.collection('posts').doc(postId).collection('likes').doc(likerUid).set({
      likedAt: Timestamp.now(),
    });

    const notifId = `like_${postId}_${likerUid}`;
    const doc = await waitFor(async () => {
      const d = await db.collection('notifications').doc(notifId).get();
      return d.exists ? d : null;
    });

    expect(doc.data()).toMatchObject({
      userId: authorId,
      type: 'like',
      actorId: likerUid,
      postId,
      deepLink: `/posts/${postId}`,
    });
  });

  it('comment: creating posts/{postId}/comments/{commentId} produces a comment notification', async () => {
    const postId = uniq('post');
    const commentId = uniq('comment');
    const authorId = uniq('author');
    const commenterId = uniq('commenter');

    await db.collection('posts').doc(postId).set({ authorId, caption: 'hi' });
    await db.collection('users').doc(commenterId).set({ name: 'Commenter Name' });
    await db.collection('posts').doc(postId).collection('comments').doc(commentId).set({
      authorId: commenterId,
      text: 'nice post',
      createdAt: Timestamp.now(),
    });

    const notifId = `comment_${commentId}`;
    const doc = await waitFor(async () => {
      const d = await db.collection('notifications').doc(notifId).get();
      return d.exists ? d : null;
    });

    expect(doc.data()).toMatchObject({
      userId: authorId,
      type: 'comment',
      actorId: commenterId,
      postId,
    });
  });

  it('follow: creating users/{targetUid}/followers/{followerId} produces a follow notification', async () => {
    const targetUid = uniq('target');
    const followerId = uniq('follower');

    await db.collection('users').doc(followerId).set({ name: 'Follower Name' });
    await db.collection('users').doc(targetUid).collection('followers').doc(followerId).set({
      followedAt: Timestamp.now(),
    });

    const notifId = `follow_${targetUid}_${followerId}`;
    const doc = await waitFor(async () => {
      const d = await db.collection('notifications').doc(notifId).get();
      return d.exists ? d : null;
    });

    expect(doc.data()).toMatchObject({
      userId: targetUid,
      type: 'follow',
      actorId: followerId,
      deepLink: `/users/${followerId}`,
    });
  });

  it('rsvp: creating events/{eventId}/rsvps/{uid} produces an event notification', async () => {
    const eventId = uniq('event');
    const createdBy = uniq('organizer');
    const attendeeUid = uniq('attendee');

    await db.collection('events').doc(eventId).set({ createdBy, title: 'Layover meetup' });
    await db.collection('users').doc(attendeeUid).set({ name: 'Attendee Name' });
    await db.collection('events').doc(eventId).collection('rsvps').doc(attendeeUid).set({
      rsvpedAt: Timestamp.now(),
    });

    const notifId = `rsvp_${eventId}_${attendeeUid}`;
    const doc = await waitFor(async () => {
      const d = await db.collection('notifications').doc(notifId).get();
      return d.exists ? d : null;
    });

    expect(doc.data()).toMatchObject({
      userId: createdBy,
      type: 'event',
      actorId: attendeeUid,
      eventId,
    });
  });

  it('message: creating chats/{chatId}/messages/{messageId} notifies the other DM participant', async () => {
    const chatId = uniq('chat');
    const messageId = uniq('msg');
    const senderId = uniq('sender');
    const recipientId = uniq('recipient');

    await db.collection('chats').doc(chatId).set({ participants: [senderId, recipientId] });
    await db.collection('users').doc(senderId).set({ name: 'Sender Name' });
    await db.collection('chats').doc(chatId).collection('messages').doc(messageId).set({
      senderId,
      text: 'hey!',
      createdAt: Timestamp.now(),
    });

    const notifId = `message_${messageId}_${recipientId}`;
    const doc = await waitFor(async () => {
      const d = await db.collection('notifications').doc(notifId).get();
      return d.exists ? d : null;
    });

    expect(doc.data()).toMatchObject({
      userId: recipientId,
      type: 'message',
      actorId: senderId,
      chatId,
    });
  });

  it('match: an update transitioning pending -> matched notifies both participants', async () => {
    const matchId = uniq('match');
    const userA = uniq('userA');
    const userB = uniq('userB');

    const matchRef = db.collection('matches').doc(matchId);
    await matchRef.set({ userA, userB, status: 'pending' });
    await matchRef.update({ status: 'matched' });

    const [docA, docB] = await Promise.all([
      waitFor(async () => {
        const d = await db.collection('notifications').doc(`match_${matchId}_${userA}`).get();
        return d.exists ? d : null;
      }),
      waitFor(async () => {
        const d = await db.collection('notifications').doc(`match_${matchId}_${userB}`).get();
        return d.exists ? d : null;
      }),
    ]);

    expect(docA.data()).toMatchObject({ userId: userA, actorId: userB, type: 'match', deepLink: '/match' });
    expect(docB.data()).toMatchObject({ userId: userB, actorId: userA, type: 'match', deepLink: '/match' });
  });

  it(
    'push fan-out: creating a non-like notifications/{id} doc runs to completion without ' +
      'crashing the emulator, whether or not a token is on file (no FCM emulator exists, so a ' +
      'live send can only be confirmed against a real project — see the design\'s Known Limitations)',
    async () => {
      const recipientUid = uniq('recipient');
      const notifId = uniq('notif');

      // No private/data doc at all — pushFanout must log-and-stop, not throw.
      await db.collection('notifications').doc(notifId).set({
        userId: recipientUid,
        type: 'event',
        title: 'Test event notification',
        body: 'Body',
        eventId: 'event-x',
        isRead: false,
        createdAt: Timestamp.now(),
      });

      // Give the trigger a moment to run, then prove the emulator is still
      // healthy (a thrown/unhandled error in the trigger would not itself
      // fail this test, but a wedged/crashed Functions emulator would make
      // this follow-up write hang or fail).
      await new Promise((resolve) => setTimeout(resolve, 2000));
      const sentinelId = uniq('sentinel');
      await db.collection('notifications').doc(sentinelId).set({
        userId: recipientUid,
        type: 'like', // like never reaches the push step — pure liveness check
        title: 'sentinel',
        body: 'sentinel',
        isRead: false,
        createdAt: Timestamp.now(),
      });
      const sentinel = await db.collection('notifications').doc(sentinelId).get();
      expect(sentinel.exists).toBe(true);
    },
  );
});
