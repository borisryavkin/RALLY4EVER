import { Firestore, Timestamp } from "firebase-admin/firestore";
import { fail, hash } from "./domain";

export async function rateLimit(
  db: Firestore,
  scope: string,
  key: string,
  limit: number,
  windowMs: number,
  now = Date.now(),
): Promise<void> {
  const ref = db.doc(`rateLimits/${scope}-${hash(key)}`);
  await db.runTransaction(async (tx) => {
    const old = (await tx.get(ref)).data();
    const resetAt = old?.resetAt?.toMillis() ?? 0;
    if (resetAt > now && old!.count >= limit)
      fail(
        "resource-exhausted",
        "rate-limit",
        "Too many attempts; please try again later",
        { retryAfterSeconds: Math.ceil((resetAt - now) / 1000) },
      );
    tx.set(ref, {
      count: resetAt > now ? old!.count + 1 : 1,
      resetAt: Timestamp.fromMillis(resetAt > now ? resetAt : now + windowMs),
    });
  });
}
