import { createHash } from 'node:crypto';
const slug = (s) => String(s ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const zone = {NSW:'Australia/Sydney',ACT:'Australia/Sydney',VIC:'Australia/Melbourne',QLD:'Australia/Brisbane',SA:'Australia/Adelaide',WA:'Australia/Perth',NT:'Australia/Darwin',TAS:'Australia/Hobart'};

// Preview only. Source status is preserved for review; no dated sessions inferred.
export function preparePrograms(sources) {
  const rows = new Map();
  for (const {name, programs} of sources) {
    for (const p of programs) {
      const sport = String(p.sport ?? 'tennis').toLowerCase();
      const state = p.state ?? 'NSW';
      const key = `${state}-${sport}-${slug(p.name)}`.toLowerCase();
      const id = key.length <= 110 ? key : `${key.slice(0,100)}-${createHash('sha256').update(key).digest('hex').slice(0,8)}`;
      const lat = Number.isFinite(p.latitude) ? p.latitude : null, lng = Number.isFinite(p.longitude) ? p.longitude : null;
      const old = rows.get(id);
      const venue = {name: p.venueName || `${p.name} (venue to verify)`,address: p.address ?? '',suburb:p.suburb ?? p.name,postcode:p.postcode ?? '',state,lat,lng};
      const conflicts = old?.sourceConflicts ?? [];
      if (old && slug(old.venue.name) !== slug(venue.name)) conflicts.push(`${name}: venue differs; review source files`);
      rows.set(id, {
        id,name:old?.name ?? p.name,sport,status:'draft',venue:old?.venue.lat != null ? old.venue : venue,
        timezone:zone[state] ?? 'Australia/Sydney',scheduleText:[p.scheduleText,p.timeText,p.durationText].filter(Boolean).join(' · ') || 'Schedule to verify',
        coachUids:[],coachNames:[...new Set([...(old?.coachNames ?? []),...(p.coaches ?? [])])],
        notes:(p.additionalNotes ?? []).join('\n'),photoUrl:'',capacity:null,registrationStatus:'closed',
        needsVerification:true,sourceEntries:[...(old?.sourceEntries ?? []),{file:name,id:p.id,status:p.status ?? 'unknown'}],sourceConflicts:conflicts,revision:1,
      });
    }
  }
  return [...rows.values()].sort((a,b)=>a.name.localeCompare(b.name));
}
