import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {readForms} from '../../scripts/publish-forms.mjs';
test('all four approved legal texts retain their reviewed bytes and version',async()=>{
 const manifest=JSON.parse(await readFile(new URL('../../docs/forms/manifest.json',import.meta.url)));
 const forms=await readForms();
 assert.deepEqual(forms.map(f=>f.id),['conduct','waiver','photo-release','data-collection']);
 for(const f of forms){assert.equal(f.version,'2026-11-20');assert.equal(createHash('sha256').update(f.body).digest('hex'),manifest.forms.find(x=>x.id===f.id).sha256);assert.ok(!f.body.includes('We provide free tennis'));}
 assert.ok(forms[0].body.includes('Termination of employment, with or without notice '));
 assert.ok(forms[1].body.startsWith('RALLY4EVER Waive and Release\n'));
 assert.ok(forms[2].body.startsWith('Photo Release \n'));
});
test('reviewed Humanitix import includes only venue programs and published occurrences',async()=>{
 const {reviewedPlan}=await import('../../scripts/import-humanitix.mjs');
 const p=await reviewedPlan();assert.deepEqual(p.map(x=>x.occurrences.length),[34,2]);
 assert.equal(p[0].venue.lat,-33.878);assert.equal(p[1].venue.lat,-33.9151103);
 assert.ok(p[0].occurrences.some(e=>e.startDate.endsWith('+1000')));
 assert.ok(p.every(x=>!x.url.includes('community-tennis-and-pickleball-programs')));
});
