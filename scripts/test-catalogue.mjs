import {readFile,writeFile,unlink} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const config=JSON.parse(await readFile(new URL('../firebase.json',import.meta.url),'utf8'));
config.firestore.rules=fileURLToPath(new URL('../firestore.rules',import.meta.url));
config.firestore.indexes=fileURLToPath(new URL('../firestore.indexes.json',import.meta.url));
config.emulators={auth:{host:'127.0.0.1',port:23999},firestore:{host:'127.0.0.1',port:23880},ui:{enabled:false},hub:{host:'127.0.0.1',port:24400},logging:{host:'127.0.0.1',port:24401},singleProjectMode:true};
const generated=new URL('../.firebase.catalogue-tests.generated.json',import.meta.url);
const env={...process.env,GCLOUD_PROJECT:'demo-rally4ever',GOOGLE_CLOUD_PROJECT:'demo-rally4ever'};
for(const key of ['GOOGLE_APPLICATION_CREDENTIALS','FIREBASE_CONFIG','FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST','FIREBASE_EMULATOR_HUB','FUNCTIONS_EMULATOR_HOST']) delete env[key];
const regression=new URL('../tests/rules/.catalogue-regression.test.mjs',import.meta.url);
let oldRules=await readFile(new URL('../tests/rules/firestore.test.mjs',import.meta.url),'utf8');
oldRules=oldRules.replace("import {requireEmulators, projectId} from '../../scripts/emulator-env.mjs';", "const projectId='demo-rally4ever'; function requireEmulators(){if(process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:23880'||process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:23999')throw new Error('Isolated test emulators required');}").replaceAll('port:8080','port:23880');
if(oldRules.includes('8080') || !oldRules.includes('port:23880') || oldRules.includes('{requireEmulators, projectId}')) throw new Error('Legacy rules harness changed; refusing to risk the development emulator');
let ownConfig=false,ownRegression=false;
try{
 await writeFile(generated,JSON.stringify(config,null,2),{flag:'wx',mode:0o600});ownConfig=true;
 await writeFile(regression,oldRules,{flag:'wx',mode:0o600});ownRegression=true;
 const code=await new Promise((resolve,reject)=>{const child=spawn(fileURLToPath(new URL('../node_modules/.bin/firebase',import.meta.url)),['emulators:exec','--project','demo-rally4ever','--config',fileURLToPath(generated),'--only','auth,firestore','node --test --test-concurrency=1 tests/catalogue/emulator.test.mjs tests/rules/.catalogue-regression.test.mjs'],{cwd:root,env,stdio:'inherit'});child.on('error',reject);child.on('exit',resolve);});process.exitCode=code??1;
}finally{if(ownConfig)await unlink(generated);if(ownRegression)await unlink(regression); }
