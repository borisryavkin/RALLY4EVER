#!/usr/bin/env python3
"""Read-only AAB inspection. Never uploads, changes Firebase, or prints passwords."""
import argparse, hashlib, json, os, re, subprocess, tempfile, zipfile
from pathlib import Path
from xml.etree import ElementTree as ET
p=argparse.ArgumentParser();p.add_argument('--bundletool',required=True,type=Path);p.add_argument('--bundle',type=Path,default=Path('build/app/outputs/bundle/stagingRelease/app-staging-release.aab'));p.add_argument('--java-home',type=Path,default=Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home'));p.add_argument('--package',default='org.raly4ever');p.add_argument('--version-name',required=True);p.add_argument('--version-code',required=True);a=p.parse_args()
root=Path(__file__).resolve().parent.parent
bundle=(root/a.bundle).resolve();java=a.java_home/'bin/java';keytool=a.java_home/'bin/keytool'
def run(args,env=None):
 r=subprocess.run([str(x) for x in args],text=True,capture_output=True,env=env)
 if r.returncode:raise RuntimeError('Verification command failed: '+str(args[0])+' '+r.stderr[:400])
 return r.stdout
run([java,'-jar',a.bundletool,'validate','--bundle='+str(bundle)])
xml=run([java,'-jar',a.bundletool,'dump','manifest','--bundle='+str(bundle),'--module=base'])
m=ET.fromstring(xml);android='{http://schemas.android.com/apk/res/android}'
assert m.attrib['package']==a.package,m.attrib
assert m.attrib[android+'versionCode']==a.version_code,m.attrib
assert m.attrib[android+'versionName']==a.version_name,m.attrib
with tempfile.TemporaryDirectory(prefix='r4e-aab-') as temp:
 with zipfile.ZipFile(bundle) as z:z.extractall(temp)
 libs=list(Path(temp).glob('base/lib/*/libapp.so'));assert libs,'Missing release AOT library'
 architectures=[]
 for lib in libs:
  data=lib.read_bytes();assert b'rally4ever-3adaf' in data,'Staging project missing in '+str(lib)
  architectures.append(lib.parent.name)
cert=run([keytool,'-printcert','-jarfile',bundle]);match=re.search(r'SHA1:\s*([0-9A-F:]+)',cert);assert match,'Bundle is not signed'
props={}
for line in (root/'android/key.properties').read_text().splitlines():
 if '=' in line and not line.lstrip().startswith('#'):
  k,v=line.split('=',1);props[k.strip()]=v.strip()
store=Path(props['storeFile']);store=store if store.is_absolute() else root/'android/app'/store
expected=run([keytool,'-list','-v','-keystore',store,'-alias',props['keyAlias'],'-storepass:env','R4E_VERIFY_STORE_PASSWORD'],env={**os.environ,'R4E_VERIFY_STORE_PASSWORD':props['storePassword']})
expectedSha=re.search(r'SHA1:\s*([0-9A-F:]+)',expected).group(1);assert match.group(1)==expectedSha,'Upload certificate mismatch'
verified=run([a.java_home/'bin/jarsigner','-verify',bundle]);assert 'jar verified' in verified,'JAR signature verification failed'
print(json.dumps({'bundle':str(bundle),'bytes':bundle.stat().st_size,'sha256':hashlib.sha256(bundle.read_bytes()).hexdigest(),'package':a.package,'versionName':a.version_name,'versionCode':int(a.version_code),'projectId':'rally4ever-3adaf','verifiedArchitectures':architectures,'uploadCertificateSha1':expectedSha,'uploadKeystoreMatches':True,'bundletoolValid':True,'jarSignatureVerified':True},indent=2))
