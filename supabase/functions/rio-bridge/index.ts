import { makeHandler } from './core.mjs';
Deno.serve(makeHandler(async (args: unknown) => {
  const response = await fetch(Deno.env.get('SUPABASE_URL') + '/rest/v1/rpc/rio_readonly_request', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, Authorization: 'Bearer ' + Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')! },
    body: JSON.stringify(args), signal: AbortSignal.timeout(8000)
  });
  if (!response.ok) throw new Error('database_unavailable');
  return await response.json();
}));
