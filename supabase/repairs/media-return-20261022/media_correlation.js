export function matchingRun(runs, dispatch) {
  if (!/^[0-9a-f]{40}$/.test(dispatch.commit_sha || "")) return null;
  const earliest = Date.parse(dispatch.created_at) - 5000;
  return runs.filter(run =>
    run.event === "workflow_dispatch" &&
    run.head_sha === dispatch.commit_sha &&
    Date.parse(run.created_at) >= earliest
  ).sort((a,b) => Date.parse(a.created_at)-Date.parse(b.created_at))[0] || null;
}
