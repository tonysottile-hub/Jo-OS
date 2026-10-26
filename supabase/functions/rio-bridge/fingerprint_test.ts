import { approvalFingerprint, canonicalApprovedContent, type ApprovedContent } from "./fingerprint.ts";
const assert = (condition: boolean, message: string) => { if (!condition) throw new Error(message); };
const base: ApprovedContent = {
  caption: "Cigar 30  ",
  destination: "facebook_page_cigar30",
  media: [
    { hash_sha256: "a".repeat(64), mime: "image/png", order: 1 },
    { hash_sha256: "b".repeat(64), mime: "image/png", order: 2 },
  ],
  scheduled_publish_time: null,
};
Deno.test("canonical representation has deterministic key order", () => {
  assert(canonicalApprovedContent(base) === JSON.stringify({
    caption: base.caption, destination: base.destination,
    media: base.media, scheduled_publish_time: null,
  }), "canonical form changed");
});
Deno.test("exact approved caption changes fingerprint, including whitespace", async () => {
  assert(await approvalFingerprint(base) !== await approvalFingerprint({ ...base, caption: "Cigar 30 " }), "caption whitespace ignored");
});
Deno.test("media order changes fingerprint", async () => {
  const reversed = [...base.media].reverse().map((m, i) => ({ ...m, order: i + 1 }));
  assert(await approvalFingerprint(base) !== await approvalFingerprint({ ...base, media: reversed }), "media order ignored");
});
Deno.test("media bytes hash changes fingerprint", async () => {
  const media = [{ ...base.media[0], hash_sha256: "c".repeat(64) }, base.media[1]];
  assert(await approvalFingerprint(base) !== await approvalFingerprint({ ...base, media }), "media hash ignored");
});
Deno.test("scheduled time changes fingerprint", async () => {
  assert(await approvalFingerprint(base) !== await approvalFingerprint({ ...base, scheduled_publish_time: "2026-10-26T14:00:00Z" }), "schedule ignored");
});
Deno.test("rejects invalid media hash and nonsequential order", () => {
  for (const media of [[{ ...base.media[0], hash_sha256: "invalid" }], [{ ...base.media[0], order: 2 }]]) {
    let threw = false;
    try { canonicalApprovedContent({ ...base, media }); } catch { threw = true; }
    assert(threw, "invalid media accepted");
  }
});
