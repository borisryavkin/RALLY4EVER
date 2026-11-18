export const normalizeEmail = email => email.trim().toLowerCase();
export const identityKey = normalizeEmail;
export const demoPassword = 'Emulator-only-Password-123!';
export const accounts = [
  {uid: 'admin-1', email: 'admin@rally4ever.org', role: 'admin'},
  {uid: 'coach-1', email: 'dan@rally4ever.org', role: 'coach'},
  {uid: 'coach-2', email: 'mei@rally4ever.org', role: 'coach'},
  ...Array.from({length: 10}, (_, n) => ({uid: `participant-${n + 1}`, email: `member${n + 1}@example.test`, role: 'participant'})),
];
export function profile(account, now) {
  return {
    uid: account.uid, email: account.email, emailLower: normalizeEmail(account.email),
    role: account.role, coachEnabled: account.role === 'coach', mergedInto: null, createdAt: now, updatedAt: now,
    firstName: account.uid, lastName: '', postcode: '2022', injuries: '',
    preferences: {useInReports: false, wellbeingCheckIns: false, showInWhosGoing: false, marketingEmails: false},
    about: {},
  };
}
// mobile/emergencyContact live in users/{uid}/private/contact, not the main
// profile -- see firestore.rules' validContact.
export function contact(now, extra = {}) {
  return {
    mobile: '', mobileVerified: false, emergencyContact: {name: '', mobile: ''},
    visibleToCoachUids: [], updatedAt: now, ...extra,
  };
}
export function event(id, coachUid, startsAt, endsAt) {
  return {
    eventId: id, code: id.toUpperCase(), name: `Rally ${id}`, sport: 'tennis', status: 'published',
    startsAt, endsAt, timezone: 'Australia/Sydney', coachUids: [coachUid],
    venue: {name: 'Waverley Park', address: 'Bondi Junction NSW', lat: -33.8926, lng: 151.2511},
    geofenceRadiusM: 150, requiredFormIds: ['conduct', 'waiver'],
  };
}
