import { App } from "firebase-admin/app";
import { getStorage } from "firebase-admin/storage";
import { fail } from "./domain";
export function withoutDownloadToken(metadata: Record<string, string> = {}) {
  // Firebase uploads may auto-generate bearer download tokens. Never retain one
  // on managed images: public reads now use explicit Storage rules, without bearer tokens.
  return { ...metadata, firebaseStorageDownloadTokens: null };
}
export async function sealVenuePhoto(app: App, url: string) {
  if (
    process.env.FUNCTIONS_EMULATOR === "true" &&
    !process.env.FIREBASE_STORAGE_EMULATOR_HOST
  )
    fail(
      "failed-precondition",
      "storage-emulator-required",
      "Start the Storage emulator before uploading photos",
    );
  const prefix = "gs://rally4ever-3adaf.firebasestorage.app/";
  if (!url.startsWith(prefix))
    fail(
      "invalid-argument",
      "venue-photo-path",
      "Invalid managed photo bucket",
    );
  const file = getStorage(app)
    .bucket("rally4ever-3adaf.firebasestorage.app")
    .file(url.slice(prefix.length));
  const [metadata] = await file.getMetadata();
  if (
    !["image/jpeg", "image/png", "image/webp"].includes(
      metadata.contentType ?? "",
    ) ||
    Number(metadata.size) > 5 * 1024 * 1024
  )
    fail("invalid-argument", "invalid-photo", "Use an image under 5 MB");
  await file.setMetadata({
    metadata: withoutDownloadToken(
      metadata.metadata as Record<string, string>,
    ) as any,
  });
}
