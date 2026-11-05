const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");

function hashTicket(value) {
  if (typeof value !== "string" || value.length < 32 || value.length > 256) throw new Error("invalid");
  return crypto.createHash("sha256").update(value, "utf8").digest("hex");
}

test("ticket credentials hash deterministically without exposing the credential", () => {
  const credential = "a".repeat(48);
  const digest = hashTicket(credential);
  assert.equal(digest, hashTicket(credential));
  assert.equal(digest.length, 64);
  assert.notEqual(digest, credential);
});
test("rejects missing and undersized credentials", () => {
  assert.throws(() => hashTicket(""), /invalid/);
  assert.throws(() => hashTicket("short"), /invalid/);
  assert.throws(() => hashTicket(null), /invalid/);
});
