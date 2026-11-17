import {test} from 'node:test';
import assert from 'node:assert/strict';
import {preparePrograms} from '../../scripts/program-catalogue.mjs';

test('directory import de-duplicates by program, sport and state without inventing coordinates or sessions',()=>{
 const first={id:'old-guid',name:'Bondi',state:'NSW',sport:'tennis',status:'active',venueName:'Park courts'};
 const second={...first,id:'bondi',latitude:-33.89,longitude:151.25};
 const sources=[{name:'national',programs:[first,{...first,sport:'pickleball'},{...first,state:'WA'}]},{name:'nsw',programs:[second]}];
 const result=preparePrograms(sources);assert.equal(result.length,3);
 const bondi=result.find(p=>p.id==='nsw-tennis-bondi');assert.equal(bondi.venue.lat,-33.89);assert.equal(bondi.status,'draft');assert.equal(bondi.sourceEntries.length,2);assert.deepEqual(bondi.coachUids,[]);
 assert.equal(result.find(p=>p.id==='wa-tennis-bondi').venue.lat,null);assert.equal(bondi.startsAt,undefined);
 assert.deepEqual(preparePrograms(sources),result);
});
test('venue conflicts are surfaced and closed source status is preserved for review',()=>{
 const p={id:'x',name:'Shared suburb',state:'NSW',sport:'tennis',status:'closed',venueName:'Court one'};
 const result=preparePrograms([{name:'one',programs:[p]},{name:'two',programs:[{...p,venueName:'Court two'}]}]);
 assert.equal(result[0].sourceConflicts.length,1);assert.equal(result[0].sourceEntries[0].status,'closed');assert.equal(result[0].needsVerification,true);assert.equal(result[0].status,'draft');
});
