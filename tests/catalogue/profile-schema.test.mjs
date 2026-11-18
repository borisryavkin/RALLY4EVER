import {test} from 'node:test';
import assert from 'node:assert/strict';
import {validateMigrationTarget} from '../../scripts/migrate-profile-schema.mjs';
import {planProfileUpgrade} from '../../scripts/profile-schema.mjs';

const legacy = () => ({uid:'fixture', emailLower:'fixture@example.test', role:'participant',
  mergedInto:null, firstName:'Fixture', postcode:'2022', mobile:'0400000000',
  emergencyContact:{name:'Contact',mobile:'0400000001'}, updatedAt:'fixture-time',
  about:{ageRange:'25–34',currentActivity:'Working',referral:'Friend',culturalBackground:'Neither'}});

test('profile upgrade preserves prefilled name, age, postcode, UID, email and role', () => {
  const original=legacy(), before=structuredClone(original), plan=planProfileUpgrade(original);
  assert.deepEqual(original,before);
  for(const key of ['uid','emailLower','role','firstName','postcode']) assert.equal(plan.profile[key],original[key]);
  assert.equal(plan.profile.about.ageRange,original.about.ageRange);
  assert.equal(plan.contact.mobile,original.mobile);
  assert.deepEqual(plan.contact.emergencyContact,original.emergencyContact);
  assert.equal('mobile' in plan.profile,false);
  assert.deepEqual(plan.profile.about.occupation,['working']);
  assert.deepEqual(plan.before,{profile:original,contact:null});
  assert.equal(planProfileUpgrade(plan.profile,plan.contact).changed,false);
});
test('conflicts are held for review; merged profiles remain unchanged', () => {
  const original=legacy();
  assert.throws(()=>planProfileUpgrade(original,{...planProfileUpgrade(original).contact,mobile:'different'}),/conflicting mobile/);
  assert.throws(()=>planProfileUpgrade({...original,about:{currentActivity:'Unknown'}}),/unknown/);
  assert.deepEqual(planProfileUpgrade({...original,mergedInto:'canonical'}),{changed:false,skipped:'merged-profile'});
});

test('real migration is dry-run by default and apply needs explicit matching confirmation',()=>{
 const args=new Map([['--project','rally4ever-3adaf'],['--staging',true]]);
 assert.equal(validateMigrationTarget(args,{}),'rally4ever-3adaf');
 args.set('--apply',true);
 assert.throws(()=>validateMigrationTarget(args,{}),/confirm-project/);
 args.set('--confirm-project','demo-rally4ever');
 assert.throws(()=>validateMigrationTarget(args,{}),/confirm-project/);
 args.set('--confirm-project','rally4ever-3adaf');
 assert.equal(validateMigrationTarget(args,{}),'rally4ever-3adaf');
 assert.throws(()=>validateMigrationTarget(args,{FIRESTORE_EMULATOR_HOST:'127.0.0.1:8080'}),/refuses emulator/);
});
