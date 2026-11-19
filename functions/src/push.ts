import { getMessaging, Message } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import { db } from './common';

/** Android channel the app creates (lib/features/notifications/data/fcm_push_service.dart). */
export const ANDROID_CHANNEL_ID = 'tsl.default';

export interface Push {
  title: string;
  body: string;
  /** Small string values for the app, e.g. the work order ID. */
  data?: Record<string, string>;
}

/** The FCM message for one device. A notification message, so the phone
 * shows it while the app is in the background or closed; when the app is
 * open, the app shows it itself. */
export function pushMessage(token: string, push: Push): Message {
  return {
    token,
    notification: { title: push.title, body: push.body },
    data: push.data,
    android: {
      priority: 'high',
      notification: { channelId: ANDROID_CHANNEL_ID, sound: 'default' },
    },
    apns: { payload: { aps: { sound: 'default' } } },
  };
}

/** Errors meaning the token will never work again (app removed, signed out, …). */
const DEAD_TOKEN = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/**
 * Sends a push to each of a person's devices through Firebase Cloud
 * Messaging, and forgets devices that no longer exist. Best effort: failures
 * are logged, never thrown, so a delivery problem never undoes the action
 * that caused it.
 */
export async function sendPush(uid: string, tokens: string[], push: Push): Promise<void> {
  if (tokens.length === 0) return;
  try {
    const result = await getMessaging().sendEach(tokens.map((token) => pushMessage(token, push)));
    const dead: string[] = [];
    result.responses.forEach((response, i) => {
      if (response.success) return;
      const code = response.error?.code ?? 'unknown';
      if (DEAD_TOKEN.has(code)) dead.push(tokens[i]);
      else logger.warn(`push to ${uid} not delivered: ${code}`);
    });
    await Promise.all(dead.map((token) => db.doc(`users/${uid}/fcmTokens/${token}`).delete()));
    logger.info(`push to ${uid}: ${result.successCount} sent, ${dead.length} old devices removed`);
  } catch (error) {
    logger.warn(`push to ${uid} failed: ${(error as Error).message}`);
  }
}
