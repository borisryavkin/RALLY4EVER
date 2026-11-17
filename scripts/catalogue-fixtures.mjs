export function demoPrograms() {
  return [
    {id:'demo-bondi-tennis',name:'Demo Bondi social tennis',sport:'tennis',coachUids:['coach-1'],coachNames:['Dan'],venue:{name:'Waverley Park',address:'Park Parade',suburb:'Bondi Junction',postcode:'2022',state:'NSW',lat:-33.8926,lng:151.2511},scheduleText:'Demo weekly Tuesday session — publish dates in the calendar',capacity:12},
    {id:'demo-innerwest-pickleball',name:'Demo Inner West pickleball',sport:'pickleball',coachUids:['coach-2'],coachNames:['Mei'],venue:{name:'Demo community courts',address:'Addison Road',suburb:'Marrickville',postcode:'2204',state:'NSW',lat:-33.902,lng:151.163},scheduleText:'Demo weekly Saturday session — publish dates in the calendar',capacity:10},
  ].map(p=>({...p,status:'active',timezone:'Australia/Sydney',notes:'Synthetic emulator fixture. Equipment provided.',photoUrl:'',registrationStatus:'open',revision:1}));
}
