const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const crypto = require("node:crypto");

initializeApp();
const db = getFirestore();

function requireAuth(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  return request.auth.uid;
}
function hashTicket(value) {
  if (typeof value !== "string" || value.length < 32 || value.length > 256) {
    throw new HttpsError("invalid-argument", "Ticket credential is invalid.");
  }
  return crypto.createHash("sha256").update(value, "utf8").digest("hex");
}
async function requireOrganizer(uid) {
  const user = await db.doc(`users/${uid}`).get();
  if (!user.exists || user.get("role") !== "organizer") {
    throw new HttpsError("permission-denied", "Organizer access required.");
  }
}

exports.createGuestTicket = onCall(async (request) => {
  const uid = requireAuth(request);
  const { eventId, name, phone = "", email = "", credential } = request.data || {};
  if (typeof eventId !== "string" || typeof name !== "string" || !name.trim()) {
    throw new HttpsError("invalid-argument", "Event and guest name are required.");
  }
  const ticketHash = hashTicket(credential);
  const eventRef = db.doc(`events/${eventId}`);
  const event = await eventRef.get();
  if (!event.exists || event.get("organizerUid") !== uid) {
    throw new HttpsError("permission-denied", "You cannot add guests to this event.");
  }
  const guestRef = eventRef.collection("guests").doc();
  await guestRef.create({
    name: name.trim().slice(0, 120),
    phone: typeof phone === "string" ? phone.trim().slice(0, 40) : "",
    email: typeof email === "string" ? email.trim().slice(0, 254) : "",
    ticketHash,
    checkedIn: false,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { guestId: guestRef.id };
});

exports.assignGateStaff = onCall(async (request) => {
  const uid = requireAuth(request);
  const { eventId, staffUid } = request.data || {};
  if (typeof eventId !== "string" || typeof staffUid !== "string" || !staffUid) {
    throw new HttpsError("invalid-argument", "Event and staff user are required.");
  }
  await requireOrganizer(uid);
  const eventRef = db.doc(`events/${eventId}`);
  const event = await eventRef.get();
  if (!event.exists || event.get("organizerUid") !== uid) {
    throw new HttpsError("permission-denied", "You do not own this event.");
  }
  const staffUser = await db.doc(`users/${staffUid}`).get();
  if (!staffUser.exists || staffUser.get("role") !== "gateStaff") {
    throw new HttpsError("failed-precondition", "The account must have gateStaff role.");
  }
  await eventRef.collection("staff").doc(staffUid).set({
    uid: staffUid, assignedAt: FieldValue.serverTimestamp(), assignedBy: uid
  });
  return { assigned: true };
});

exports.checkInTicket = onCall(async (request) => {
  const uid = requireAuth(request);
  const { eventId, credential } = request.data || {};
  if (typeof eventId !== "string") throw new HttpsError("invalid-argument", "Event is required.");
  const ticketHash = hashTicket(credential);
  const eventRef = db.doc(`events/${eventId}`);
  const staffRef = eventRef.collection("staff").doc(uid);
  const userRef = db.doc(`users/${uid}`);
  const user = await userRef.get();
  const event = await eventRef.get();
  if (!event.exists) throw new HttpsError("not-found", "Event not found.");
  const isOwner = event.get("organizerUid") === uid && user.exists && user.get("role") === "organizer";
  if (!isOwner && !(await staffRef.get()).exists) {
    throw new HttpsError("permission-denied", "You are not assigned to this event.");
  }
  const matches = await eventRef.collection("guests").where("ticketHash", "==", ticketHash).limit(1).get();
  if (matches.empty) return { status: "invalid" };
  const guestRef = matches.docs[0].ref;
  return db.runTransaction(async (tx) => {
    const guest = await tx.get(guestRef);
    if (!guest.exists) return { status: "invalid" };
    if (guest.get("checkedIn") === true) return { status: "already_checked_in" };
    tx.update(guestRef, {
      checkedIn: true,
      checkedInAt: FieldValue.serverTimestamp(),
      checkedInBy: uid,
    });
    tx.update(eventRef, { attendanceCount: FieldValue.increment(1) });
    return { status: "checked_in", guestName: guest.get("name") || "Guest" };
  });
});

exports.lookupTicket = onCall(async (request) => {
  const { eventId, credential } = request.data || {};
  if (typeof eventId !== "string") throw new HttpsError("invalid-argument", "Event is required.");
  const ticketHash = hashTicket(credential);
  const eventRef = db.doc(`events/${eventId}`);
  const matches = await eventRef.collection("guests").where("ticketHash", "==", ticketHash).limit(1).get();
  if (matches.empty) throw new HttpsError("not-found", "Ticket not found.");
  const guest = matches.docs[0];
  const event = await eventRef.get();
  return {
    guestName: guest.get("name") || "Guest",
    eventTitle: event.exists ? event.get("title") : "Event",
    checkedIn: guest.get("checkedIn") === true,
  };
});
