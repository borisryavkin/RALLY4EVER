import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFunctions, httpsCallable } from "firebase/functions";
import { getStorage, ref, getBytes, uploadBytes } from "firebase/storage";
import config from "./firebase-config.generated.json";
if (config.projectId !== "rally4ever-3adaf")
  throw Error("Unexpected Firebase project");
export const app = initializeApp(config),
  auth = getAuth(app),
  storage = getStorage(app);
const functions = getFunctions(app, "australia-southeast1");
export async function call(name, data = {}) {
  return (await httpsCallable(functions, name, { timeout: 120000 })(data)).data;
}
export async function photoBytes(url) {
  return getBytes(ref(storage, url), 5 * 1024 * 1024);
}
export async function uploadVenuePhoto(venueId, blob) {
  const path = `venues/${venueId}/${crypto.randomUUID()}.jpg`;
  await uploadBytes(ref(storage, path), blob, {
    contentType: "image/jpeg",
    cacheControl: "private,max-age=3600",
  });
  return `gs://${config.storageBucket}/${path}`;
}
