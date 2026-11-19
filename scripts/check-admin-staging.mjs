// Read-only callable checks plus one intentionally denied participant Storage write.
// Existing Google accounts only. ID tokens stay in browser memory, never in reports.
import http from "node:http";
import { readFile, writeFile } from "node:fs/promises";
const cfg = JSON.parse(
  await readFile(
    new URL("../config/staging.web.json", import.meta.url),
    "utf8",
  ),
);
if (
  cfg.projectId !== "rally4ever-3adaf" ||
  process.env.FIRESTORE_EMULATOR_HOST ||
  process.env.FIREBASE_AUTH_EMULATOR_HOST
)
  throw Error("Real staging check only");
const publicConfig = Object.fromEntries(
  [
    "apiKey",
    "authDomain",
    "projectId",
    "storageBucket",
    "messagingSenderId",
    "appId",
  ].map((k) => [k, cfg[k]]),
);
const html = `<!doctype html><title>Rally4Ever admin access verification</title><style>body{font:16px system-ui;background:#001751;color:white;padding:40px;max-width:1000px}button{padding:14px;margin:8px}pre{white-space:pre-wrap}</style><h1>Admin access verification</h1><p>rally4ever-3adaf · existing Google accounts. No role or profile changes. Participant-only Storage probe must fail.</p><button id="signin">Sign in with Google</button><button id="check">Run access checks</button><button id="out">Sign out</button><pre id="result">Not signed in</pre><script type="module">
import{initializeApp}from'https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js';import{getAuth,GoogleAuthProvider,signInWithPopup,signOut,inMemoryPersistence,setPersistence}from'https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js';
const config=${JSON.stringify(publicConfig)},app=initializeApp(config),auth=getAuth(app);await setPersistence(auth,inMemoryPersistence);const out=document.querySelector('#result');
async function check(){try{const u=auth.currentUser;if(!u)throw Error('Sign in first');const t=await u.getIdTokenResult(true),rows=[{uid:u.uid,role:t.claims.role??'participant',verified:u.emailVerified}];for(const name of ['adminCatalogue','adminSaveSession','adminSaveVenue','adminRemoveDemo','listUsers','setUserRole']){if(t.claims.role==='admin'&&['adminSaveSession','adminSaveVenue','setUserRole'].includes(name))continue;const data=name==='adminSaveSession'?{changes:{}}:name==='setUserRole'?{uid:u.uid,role:'participant',reason:'Denial test; must not change account'}:{};const r=await fetch('https://australia-southeast1-rally4ever-3adaf.cloudfunctions.net/'+name,{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+t.token},body:JSON.stringify({data})});const b=await r.json();rows.push({function:name,http:r.status,status:b.error?.status??'OK',reason:b.error?.details?.reason,counts:b.result?.events?{events:b.result.events.length,programs:b.result.programs?.length,venues:b.result.venues?.length}:undefined});out.textContent=JSON.stringify(rows,null,2);}
if(t.claims.role!=='admin'){const path='venues/admin-access-check/participant-must-be-denied.jpg';const r=await fetch('https://firebasestorage.googleapis.com/v0/b/'+config.storageBucket+'/o?name='+encodeURIComponent(path),{method:'POST',headers:{authorization:'Firebase '+t.token,'content-type':'image/jpeg'},body:new Uint8Array([255,216,255,217])});rows.push({storage:'participant venue write',http:r.status,expected:403});}
out.textContent=JSON.stringify(rows,null,2);await fetch('/proof',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(rows)});}catch(e){out.textContent=e.code+': '+e.message;}}
document.querySelector('#signin').onclick=async()=>{try{const p=new GoogleAuthProvider();p.setCustomParameters({prompt:'select_account'});await signInWithPopup(auth,p);await check();}catch(e){out.textContent=e.code+': '+e.message;}};document.querySelector('#check').onclick=check;document.querySelector('#out').onclick=async()=>{await signOut(auth);out.textContent='Signed out';};
</script>`;
http
  .createServer(async (req, res) => {
    if (req.url === "/proof" && req.method === "POST") {
      let body = "";
      for await (const c of req) body += c;
      if (body.length > 10000) {
        res.writeHead(413).end();
        return;
      }
      let rows;
      try {
        rows = JSON.parse(body);
      } catch {
        res.writeHead(400).end();
        return;
      }
      if (!Array.isArray(rows)) {
        res.writeHead(400).end();
        return;
      }
      const path = "/tmp/r4e-web-admin-access-proof-" + Date.now() + ".json";
      await writeFile(path, JSON.stringify(rows, null, 2), { mode: 0o600 });
      console.log("Status-only proof saved: " + path);
      res.end("Recorded");
      return;
    }
    res.setHeader("content-type", "text/html");
    res.end(html);
  })
  .listen(57831, "127.0.0.1", () =>
    console.log("Real access check http://localhost:57831"),
  );
