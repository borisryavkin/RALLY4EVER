import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFunctions, httpsCallable } from "firebase/functions";
import { getStorage, ref, getBytes, uploadBytesResumable } from "firebase/storage";
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
export async function uploadPhoto(kind, id, blob, onProgress = () => {}) {
  const folder = kind === 'session' ? 'sessions' : 'venues';
  const path = `${folder}/${id}/${Date.now()}-${crypto.randomUUID()}.jpg`;
  const task = uploadBytesResumable(ref(storage, path), blob, {contentType:'image/jpeg',cacheControl:'public,max-age=3600'});
  await new Promise((resolve,reject)=>task.on('state_changed',s=>onProgress(s.totalBytes?s.bytesTransferred/s.totalBytes:0),reject,resolve));
  return `https://firebasestorage.googleapis.com/v0/b/${config.storageBucket}/o/${encodeURIComponent(path)}?alt=media`;
}
export async function uploadVenuePhoto(venueId, blob, progress) { return uploadPhoto('venue',venueId,blob,progress); }
