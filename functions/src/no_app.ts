import { randomBytes } from "node:crypto";
import { DocumentData, Timestamp } from "firebase-admin/firestore";
import { AttendanceService } from "./service";
import {
  input,
  normalizeEmail,
  text,
  id,
  coordinate,
  checkDistance,
  secretMatches,
  fail,
  hash,
} from "./domain";
import { rateLimit } from "./rate_limits";

export class NoAppService {
  constructor(readonly service: AttendanceService) {}
  async validate(data: DocumentData) {
    const { db } = this.service;
    const code = id(data.eventCode, "eventCode"),
      secret = text(data.secret, "secret", 128);
    const lat = coordinate(data.lat, "lat"),
      lng = coordinate(data.lng, "lng");
    return db.runTransaction(async (tx) => {
      const found = await tx.get(
        db.collection("events").where("code", "==", code).limit(2),
      );
      if (found.size !== 1)
        fail("not-found", "event-not-found", "Event not found");
      const e = found.docs[0].data(),
        eventId = found.docs[0].id;
      this.service.window(e);
      const k = (await tx.get(db.doc(`eventSecrets/${eventId}`))).data();
      if (
        !k ||
        k.expiresAt.toMillis() <= this.service.now() ||
        !secretMatches(secret, k.currentSecretHash)
      )
        fail(
          "permission-denied",
          "invalid-secret",
          "Scan a current code from your coach",
        );
      checkDistance(
        lat,
        lng,
        e.venue.lat,
        e.venue.lng,
        e.geofenceRadiusM ?? 150,
      );
      return { e, eventId };
    });
  }
  async begin(value: unknown, remoteAddress: string) {
    const d = input(value, [
      "email",
      "eventCode",
      "secret",
      "lat",
      "lng",
      "firstName",
      "mobile",
      "emergencyContact",
      "injuries",
      "signedVersions",
    ]);
    const email = normalizeEmail(d.email);
    await rateLimit(
      this.service.db,
      "noapp-ip",
      remoteAddress,
      10,
      60000,
      this.service.now(),
    );
    const { e } = await this.validate(d);
    const mapping = await this.service.db.doc(`emailIdentities/${email}`).get();
    const prior = mapping.exists
      ? await this.service.db
          .collection("checkins")
          .where("uid", "==", mapping.data()!.uid)
          .limit(1)
          .get()
      : null;
    // Optional venue policy, enabled by default. Clients cannot turn it off.
    if (
      prior &&
      !prior.empty &&
      e.requireReturningEmailVerification !== false
    ) {
      await rateLimit(
        this.service.db,
        "noapp-email",
        email,
        3,
        3600000,
        this.service.now(),
      );
      const requestId = randomBytes(24).toString("hex");
      const { secret, ...safeData } = d;
      await this.service.db.doc(`noAppRequests/${requestId}`).create({
        email,
        data: safeData,
        secretHash: hash(secret as string),
        createdAt: this.service.stamp(),
        expiresAt: Timestamp.fromMillis(this.service.now() + 900000),
        consumed: false,
      });
      const response = await fetch(
        "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=demo-api-key",
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            requestType: "EMAIL_SIGNIN",
            email,
            continueUrl: `http://localhost:7357/?noAppRequest=${requestId}`,
            canHandleCodeInApp: true,
          }),
        },
      );
      if (!response.ok)
        fail("internal", "email-link-failed", "Unable to send a sign-in link");
      return { status: "verification-required", requestId };
    }
    return this.submit(d, email);
  }
  async complete(value: unknown, remoteAddress: string) {
    const d = input(value, ["requestId", "oobCode", "secret"]);
    await rateLimit(
      this.service.db,
      "noapp-verify",
      remoteAddress,
      5,
      60000,
      this.service.now(),
    );
    const ref = this.service.db.doc(
        `noAppRequests/${id(d.requestId, "requestId")}`,
      ),
      request = (await ref.get()).data();
    if (
      !request ||
      request.consumed ||
      request.expiresAt.toMillis() <= this.service.now()
    )
      fail(
        "failed-precondition",
        "verification-expired",
        "Request a new sign-in link",
      );
    const secret = text(d.secret, "secret", 128);
    if (hash(secret) !== request.secretHash)
      fail(
        "permission-denied",
        "invalid-secret",
        "Use the QR code that started this request",
      );
    const response = await fetch(
      "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithEmailLink?key=demo-api-key",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          email: request.email,
          oobCode: text(d.oobCode, "oobCode", 2048),
        }),
      },
    );
    if (!response.ok)
      fail(
        "permission-denied",
        "verification-invalid",
        "This sign-in link is invalid or has already been used",
      );
    const proof = (await response.json()) as { localId: string; email: string };
    const account = await this.service.auth.getUser(proof.localId);
    if (
      !account.emailVerified ||
      normalizeEmail(account.email) !== request.email
    )
      fail(
        "permission-denied",
        "verification-invalid",
        "Email verification failed",
      );
    await ref.update({ consumed: true, verifiedAt: this.service.stamp() });
    return this.submit(
      { ...request.data, secret },
      request.email,
      proof.localId,
    );
  }
  async submit(d: DocumentData, email: string, verifiedUid?: string) {
    const { eventId, e } = await this.validate(d);
    let account;
    try {
      account = await this.service.auth.getUserByEmail(email);
    } catch (error) {
      if ((error as { code?: string }).code !== "auth/user-not-found")
        throw error;
      try {
        account = await this.service.auth.createUser({
          email,
          emailVerified: false,
        });
      } catch (e) {
        if ((e as { code?: string }).code !== "auth/email-already-exists")
          throw e;
        account = await this.service.auth.getUserByEmail(email);
      }
    }
    const identity = await this.service.reserveIdentity(account.uid, email);
    if (verifiedUid && identity.uid !== verifiedUid)
      fail(
        "failed-precondition",
        "identity-conflict",
        "Sign in to your canonical account",
      );
    const firstName = text(d.firstName, "firstName", 100),
      mobile = text(d.mobile, "mobile", 40),
      contact = input(d.emergencyContact, ["name", "mobile"]);
    const emergencyContact = {
      name: text(contact.name, "emergencyContact.name", 200),
      mobile: text(contact.mobile, "emergencyContact.mobile", 40),
    };
    const versions = input(d.signedVersions, e.requiredFormIds);
    await this.service.db.runTransaction(async (tx) => {
      const profile = await tx.get(
        this.service.db.doc(`users/${identity.uid}`),
      );
      const receipts = [];
      for (const formId of e.requiredFormIds) {
        const f = await tx.get(this.service.db.doc(`forms/${formId}`));
        const current = await tx.get(
          this.service.db.doc(`consents/${identity.uid}_${formId}`),
        );
        if (
          f.exists &&
          current.data()?.version === f.data()!.version &&
          current.data()?.formType === f.data()!.formType
        )
          continue;
        if (!f.exists || versions[formId] !== f.data()!.version)
          fail(
            "failed-precondition",
            "unsigned-forms",
            "Read and accept each current form",
            { missingForms: [formId] },
          );
        receipts.push({
          uid: identity.uid,
          formId,
          formType: f.data()!.formType,
          version: f.data()!.version,
          signedAt: this.service.stamp(),
        });
      }
      const p = profile.data()!,
        fill: DocumentData = { updatedAt: this.service.stamp() };
      if (!p.firstName) fill.firstName = firstName;
      if (!p.mobile) fill.mobile = mobile;
      if (!p.emergencyContact?.name) fill.emergencyContact = emergencyContact;
      if (!p.injuries)
        fill.injuries =
          d.injuries === undefined ? "" : text(d.injuries, "injuries", 2000, 0);
      tx.update(profile.ref, fill);
      for (const receipt of receipts)
        tx.set(
          this.service.db.doc(`consents/${identity.uid}_${receipt.formId}`),
          receipt,
        );
    });
    const result = await this.service.checkIn(
      { uid: identity.uid, email },
      {
        eventCode: d.eventCode,
        secret: d.secret,
        lat: d.lat,
        lng: d.lng,
        method: "camera",
      },
      {
        walkIn: true,
        identityVerification: verifiedUid ? "email-link" : "email-only",
      },
    );
    return {
      status: "pending",
      checkinId: result.checkinId,
      eventId,
      verification: verifiedUid ? "email-link" : "email-only",
    };
  }
}
