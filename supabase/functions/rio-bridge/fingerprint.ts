// Rio bridge exact-content fingerprinting. No publishing side effects.
// Canonical form is explicit to avoid JS object-order ambiguity.
export type ApprovedMedia = { hash_sha256: string; mime: string; order: number };
export type ApprovedContent = {
  caption: string;
  destination: string;
  media: ApprovedMedia[];
  scheduled_publish_time: string | null;
};
const HEX64 = /^[0-9a-f]{64}$/;
export function canonicalApprovedContent(p: ApprovedContent): string {
  if (typeof p.caption !== "string" || typeof p.destination !== "string" ||
      !Array.isArray(p.media) || !(p.scheduled_publish_time === null ||
      (typeof p.scheduled_publish_time === "string" &&
       /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(p.scheduled_publish_time) &&
       !Number.isNaN(Date.parse(p.scheduled_publish_time))))) {
    throw new Error("invalid_approved_content");
  }
  const media = p.media.map((m, i) => {
    if (!m || m.order !== i + 1 || !HEX64.test(m.hash_sha256) ||
        typeof m.mime !== "string" || !m.mime) throw new Error("invalid_media");
    return { hash_sha256: m.hash_sha256, mime: m.mime, order: m.order };
  });
  // Sorted keys at every object level. Preserve caption bytes and media array order.
  return JSON.stringify({
    caption: p.caption,
    destination: p.destination,
    media,
    scheduled_publish_time: p.scheduled_publish_time,
  });
}
export async function approvalFingerprint(p: ApprovedContent): Promise<string> {
  const bytes = new TextEncoder().encode(canonicalApprovedContent(p));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return "sha256:" + Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, "0")).join("");
}
