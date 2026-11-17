import { logger } from 'firebase-functions';

/**
 * Company mail API, shared with SpotLat. It takes form fields `email`,
 * `subject` and `body`. Same delivery rules as SpotLat's functions:
 * always send a subject (a missing one is a spam signal), and only count a
 * send the API confirms — it has been seen to answer HTTP 200 with a bare
 * echo while dropping the mail.
 */
export const MAIL_API_URL = 'https://spotlat.com/email/send_email';
export const PUSH_API_URL = 'https://spotlat.com/Pushnotification/send';

const MAX_ATTEMPTS = 3;

/** True only when the mail API confirms it queued the message. */
export function mailApiConfirmedSend(text: string): boolean {
  if (!text) return false;
  try {
    const json = JSON.parse(text);
    return json.status === true || Boolean(json.message_id);
  } catch {
    return false; // Non-JSON, e.g. the PHP print_r echo.
  }
}

/** Sends an email, retrying up to three times. Throws if every try fails. */
export async function sendMail(email: string, subject: string, body: string): Promise<void> {
  let lastError: unknown;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const form = new FormData();
      form.append('email', email);
      form.append('subject', subject);
      form.append('body', body);
      const res = await fetch(MAIL_API_URL, { method: 'POST', body: form });
      const text = await res.text().catch(() => '');
      if (res.ok && mailApiConfirmedSend(text)) return;
      lastError = new Error(`mail API attempt ${attempt} not confirmed (HTTP ${res.status}): ${text.slice(0, 200)}`);
      logger.warn(String(lastError));
    } catch (error) {
      lastError = error;
      logger.warn(`mail API attempt ${attempt} threw: ${(error as Error).message}`);
    }
    if (attempt < MAX_ATTEMPTS) await new Promise((resolve) => setTimeout(resolve, 600 * attempt));
  }
  throw lastError ?? new Error('mail API failed after retries');
}

/**
 * Sends a push through the company push API (form fields `token` and
 * `message`, one token per call). Best effort: failures are logged, never
 * thrown, so a delivery problem never undoes the action that caused it.
 */
export async function sendPush(tokens: string[], title: string, body: string): Promise<void> {
  await Promise.all(
    tokens.map(async (token) => {
      try {
        const form = new FormData();
        form.append('token', token);
        form.append('message', `${title}\n${body}`);
        const res = await fetch(PUSH_API_URL, { method: 'POST', body: form, signal: AbortSignal.timeout(15000) });
        if (!res.ok) logger.warn(`push API returned ${res.status}: ${(await res.text()).slice(0, 200)}`);
      } catch (error) {
        logger.warn(`push API request failed: ${(error as Error).message}`);
      }
    }),
  );
}
