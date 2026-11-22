import {DocumentData} from "firebase-admin/firestore";
import {Identity, input, id, fail} from "./domain";
import {AttendanceService} from "./service";

function session(id: string, data: DocumentData) {
  return {...data, id, eventId:id, startsAt:data.startsAt.toDate().toISOString(), endsAt:data.endsAt.toDate().toISOString()};
}
export class StaffService {
  constructor(readonly service: AttendanceService) {}
  async listStaffSessions(who: Identity, value: unknown) {
    input(value, []);
    const actor=await this.service.db.runTransaction(tx=>this.service.actor(tx,who));
    if(!["admin","coach"].includes(actor.role))fail("permission-denied","staff-required","Staff access required");
    const base=this.service.db.collection("events");
    const found=await (actor.role==="admin"?base.orderBy("startsAt","desc"):base.where("coachUids","array-contains",who.uid)).limit(300).get();
    return {events:found.docs.filter(d=>!d.data().deletedAt&&!d.data().hiddenAt).map(d=>session(d.id,d.data())),limited:found.size===300};
  }
  async getEventConsole(who: Identity, value: unknown) {
    const d=input(value,["eventId"]),eventId=id(d.eventId,"eventId");
    const event=await this.service.db.runTransaction(async tx=>{
      const actor=await this.service.actor(tx,who),e=await this.service.event(tx,eventId);
      this.service.authorize(actor,who,e);return e;
    });
    const {db}=this.service;
    const [rsvps,scans]=await Promise.all([
      db.collection("rsvps").where("eventId","==",eventId).limit(500).get(),
      db.collection("checkins").where("eventId","==",eventId).limit(500).get(),
    ]);
    const intents=new Map<string, DocumentData>(rsvps.docs.map(d=>[d.data().uid,d.data()]));
    const arrivals=new Map<string, DocumentData>(scans.docs.filter(d=>!d.data().mergedInto).map(d=>[d.data().uid,{...d.data(),id:d.id}]));
    const roster=await Promise.all([...new Set([...intents.keys(),...arrivals.keys()])].map(async uid=>{
      const p=(await db.doc(`users/${uid}`).get()).data()??(await db.doc(`guests/${uid}`).get()).data(),r=intents.get(uid),c=arrivals.get(uid);
      return {uid,firstName:p?.firstName||c?.firstName||"Member",lastName:p?.lastName??"",email:p?.emailLower??"",
        countedIn:!!r && r.cancelledAt===null,checkinStatus:c?.status??null,checkinId:c?.id??null,
        scannedAt:c?.scannedAt?.toDate().toISOString()??null,distanceM:c?.distanceM??null,walkIn:c?.walkIn??false,
        correctionsCount:c?.corrections?.length??0};
    }));
    return {event:session(eventId,event),roster,limited:rsvps.size===500||scans.size===500};
  }
}
