import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ANDROID_CHANNEL_ID, pushMessage } from '../push';

test('a push is a notification message on the app channel', () => {
  const message = pushMessage('device-token', { title: 'New assignment', body: 'WO-1001', data: { kind: 'assigned' } });
  assert.equal((message as { token: string }).token, 'device-token');
  assert.deepEqual(message.notification, { title: 'New assignment', body: 'WO-1001' });
  assert.deepEqual(message.data, { kind: 'assigned' });
  assert.equal(message.android?.priority, 'high');
  assert.equal(message.android?.notification?.channelId, ANDROID_CHANNEL_ID);
});
