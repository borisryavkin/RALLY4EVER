// Pure migration planner. No Firebase calls; preserves identity and originals.
// Keep immutable Firestore Timestamp/GeoPoint instances intact when planning
// emulator transactions; structuredClone would strip their SDK prototypes.
function clone(value) {
  if (Array.isArray(value)) return value.map(clone);
  if (value && Object.getPrototypeOf(value) === Object.prototype) {
    return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, clone(entry)]));
  }
  return value;
}
const options = {
  currentActivity: ['occupation', {
    Working: 'working', Studying: 'studying', 'Looking for work': 'looking_for_work',
    Retired: 'retired', 'Prefer not to say': 'prefer_not_to_say',
  }],
  referral: ['heardAbout', {
    Friend: 'friend', 'Uni / campus': 'uni_campus', 'Social media': 'social_media',
    'Local club': 'local_club', Other: 'other',
  }],
};
const cultures = {
  'Aboriginal and/or Torres Strait Islander': 'aboriginal_torres_strait_islander',
  'Born outside Australia': 'born_outside_australia', Neither: 'neither',
  'Prefer not to say': 'prefer_not_to_say',
};

export function planProfileUpgrade(original, originalContact = null) {
  if (!original || typeof original.uid !== 'string' || !original.uid) throw new Error('Missing profile identity');
  if (original.mergedInto != null) return {changed: false, skipped: 'merged-profile'};
  const profile = clone(original);
  const about = {...profile.about};
  for (const [legacy, [current, labels]] of Object.entries(options)) {
    if (!(legacy in about)) continue;
    const value = about[legacy];
    if (value !== '' && !(value in labels)) throw new Error(`Review unknown legacy ${legacy}`);
    const mapped = value === '' ? [] : [labels[value]];
    if (current in about && JSON.stringify(about[current]) !== JSON.stringify(mapped)) throw new Error(`Review conflicting ${current}`);
    about[current] = mapped;
    delete about[legacy];
  }
  if ('referralOther' in about) {
    if ('heardAboutOther' in about && about.heardAboutOther !== about.referralOther) throw new Error('Review conflicting referral text');
    about.heardAboutOther = about.referralOther;
    delete about.referralOther;
  }
  if (typeof about.culturalBackground === 'string') {
    const value = about.culturalBackground;
    if (value !== '' && !(value in cultures)) throw new Error('Review unknown cultural background');
    about.culturalBackground = value === '' ? [] : [cultures[value]];
  }
  if (!(about.heardAbout ?? []).includes('other') && about.heardAboutOther) {
    throw new Error('Review referral text without an Other selection');
  }
  const aboutKeys = new Set(['ageRange','gender','accessNeed','occupation','heardAbout','heardAboutOther','loneliness','satisfaction','culturalBackground']);
  if (Object.keys(about).some(key => !aboutKeys.has(key))) throw new Error('Review unsupported profile answers');
  for (const [key, allowed, exclusive] of [
    ['occupation',Object.values(options.currentActivity[1]),['prefer_not_to_say']],
    ['heardAbout',Object.values(options.referral[1]),[]],
    ['culturalBackground',Object.values(cultures),['neither','prefer_not_to_say']],
  ]) {
    const selected = about[key] ?? [];
    if (!Array.isArray(selected) || new Set(selected).size !== selected.length || selected.some(v => !allowed.includes(v)) || (selected.some(v => exclusive.includes(v)) && selected.length !== 1)) throw new Error(`Review invalid ${key}`);
  }
  if ((about.heardAbout ?? []).includes('other') && !(about.heardAboutOther ?? '').trim()) throw new Error('Review Other answer without referral text');
  profile.about = about;
  const allowed = new Set(['uid','email','emailLower','role','coachEnabled','mergedInto','createdAt','updatedAt',
    'firstName','lastName','postcode','injuries','preferences','about','photoUpdatedAt','mobile','emergencyContact']);
  if (Object.keys(profile).some(key => !allowed.has(key))) throw new Error('Review unsupported profile fields');
  const contact = originalContact ? clone(originalContact) : {
    mobile: '', mobileVerified: false, emergencyContact: {name: '', mobile: ''},
    visibleToCoachUids: [], updatedAt: original.updatedAt,
  };
  if (originalContact && (Object.keys(originalContact).some(k => !['mobile','mobileVerified','emergencyContact','visibleToCoachUids','updatedAt'].includes(k)) || originalContact.mobileVerified !== false || !Array.isArray(originalContact.visibleToCoachUids))) throw new Error('Review unsupported private contact schema');
  for (const field of ['mobile', 'emergencyContact']) {
    if (!(field in profile)) continue;
    const legacy = profile[field];
    const current = contact[field];
    const empty = field === 'mobile' ? !current : !current?.name && !current?.mobile;
    if (originalContact && !empty && JSON.stringify(current) !== JSON.stringify(legacy)) {
      throw new Error(`Review conflicting ${field}; neither value was overwritten`);
    }
    if (!originalContact || empty) contact[field] = clone(legacy);
    delete profile[field];
  }
  return {
    changed: JSON.stringify(profile) !== JSON.stringify(original) || originalContact === null,
    profile, contact,
    // Required rollback snapshot; callers must store privately before applying.
    before: {profile: clone(original), contact: clone(originalContact)},
  };
}
