import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import postgres from 'npm:postgres@3.4.7';

const EXPECTED_CHANNEL = 'UCtca_WIfD_mhFSNfg_JvHgw';

function reply(message: string, status = 200) {
  return new Response(message + '\n', {
    status,
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}

function diagnostic(stage: string, detail: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ event: 'youtube_oauth_callback', stage, ...detail }));
}

async function vault(name: string, value: string, description: string) {
  const db = Deno.env.get('SUPABASE_DB_URL');
  if (!db) throw new Error('SUPABASE_DB_URL unavailable');
  const sql = postgres(db, { prepare: false, max: 1, connect_timeout: 10, idle_timeout: 5 });
  try {
    const rows = await sql`select id from vault.secrets where name=${name} limit 1`;
    if (rows.length) {
      await sql`select vault.update_secret(${String(rows[0].id)}::uuid,${value},${name},${description})`;
    } else {
      await sql`select vault.create_secret(${value},${name},${description})`;
    }
  } finally {
    await sql.end({ timeout: 2 }).catch(() => {});
  }
}

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const callback = url.searchParams.has('code') || url.searchParams.has('error');
    const cookieState = (req.headers.get('cookie') || '').split(';').map(x => x.trim())
      .find(x => x.startsWith('__Host-jo_youtube_state='))?.split('=')[1] || '';
    if (callback && (!cookieState || cookieState !== url.searchParams.get('state'))) {
      diagnostic('state_rejected');
      return reply('This authorization link is invalid or expired. Start a fresh connection.', 403);
    }

    const clientId = Deno.env.get('YOUTUBE_CLIENT_ID');
    const clientSecret = Deno.env.get('YOUTUBE_CLIENT_SECRET');
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!clientId || !clientSecret || !supabaseUrl || !serviceKey) {
      diagnostic('configuration_missing', {
        client_id: Boolean(clientId),
        client_secret: Boolean(clientSecret),
        supabase_url: Boolean(supabaseUrl),
        service_key: Boolean(serviceKey),
      });
      return reply('YouTube connection is temporarily unavailable. No publishing job was changed.', 500);
    }

    const redirectUri = supabaseUrl + '/functions/v1/youtube-oauth-helper';
    const providerError = url.searchParams.get('error');
    if (providerError) {
      diagnostic('provider_denied', { error: providerError });
      return reply('Google did not authorize YouTube publishing. No publishing job was changed.', 400);
    }

    const code = url.searchParams.get('code');
    if (!code) {
      const state = crypto.randomUUID() + crypto.randomUUID();
      const auth = new URL('https://accounts.google.com/o/oauth2/v2/auth');
      const params = {
        client_id: clientId,
        redirect_uri: redirectUri,
        response_type: 'code',
        access_type: 'offline',
        prompt: 'select_account consent',
        include_granted_scopes: 'true',
        enable_granular_consent: 'true',
        scope: 'https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube.readonly https://www.googleapis.com/auth/youtube.force-ssl',
        state,
      };
      for (const [key, value] of Object.entries(params)) auth.searchParams.set(key, value);
      diagnostic('authorization_started');
      return new Response(null, { status: 302, headers: {
        Location: auth.toString(),
        'Cache-Control': 'no-store',
        'Set-Cookie': '__Host-jo_youtube_state=' + state + '; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=600',
      }});
    }

    diagnostic('code_received');
    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: clientId,
        client_secret: clientSecret,
        redirect_uri: redirectUri,
        grant_type: 'authorization_code',
      }),
    });
    const token = await tokenResponse.json().catch(() => ({}));
    if (!tokenResponse.ok || !token.access_token) {
      diagnostic('token_exchange_failed', {
        http_status: tokenResponse.status,
        error: String(token.error || 'missing_access_token'),
        description: String(token.error_description || '').slice(0, 160),
      });
      return reply('Google authorization could not be completed. The publishing jobs remain safely paused.', 400);
    }
    if (!token.refresh_token) {
      diagnostic('refresh_token_missing');
      return reply('Google did not return offline access. Start a fresh connection and grant the requested access. No publishing job was changed.', 400);
    }
    diagnostic('token_exchange_succeeded', {
      refresh_token_returned: Boolean(token.refresh_token),
      expires_in: Number(token.expires_in || 0),
    });

    const channelResponse = await fetch(
      'https://www.googleapis.com/youtube/v3/channels?part=id,snippet&mine=true&maxResults=50',
      { headers: { Authorization: 'Bearer ' + token.access_token } },
    );
    const channelJson = await channelResponse.json().catch(() => ({}));
    const channels = Array.isArray(channelJson.items) ? channelJson.items : [];
    if (!channelResponse.ok || channels.length === 0) {
      diagnostic('channel_lookup_failed', {
        http_status: channelResponse.status,
        error: String(channelJson?.error?.status || channelJson?.error?.message || 'no_channels').slice(0, 160),
      });
      return reply('Google authorized, but no YouTube channel could be verified. The publishing jobs remain safely paused.', 400);
    }

    const channel = channels.find((item: any) => String(item?.id || '') === EXPECTED_CHANNEL);
    if (!channel) {
      diagnostic('expected_channel_missing', {
        returned_channel_ids: channels.map((item: any) => String(item?.id || '')).slice(0, 10),
        returned_channel_titles: channels.map((item: any) => String(item?.snippet?.title || '')).slice(0, 10),
      });
      return reply('The selected Google account does not expose the Unmapped America YouTube channel. The publishing jobs remain safely paused.', 400);
    }
    diagnostic('expected_channel_verified', {
      channel_id: String(channel.id),
      channel_title: String(channel?.snippet?.title || ''),
    });

    const supabase = createClient(supabaseUrl, serviceKey);
    if (token.refresh_token) {
      const { error } = await supabase.rpc('store_youtube_refresh_token', {
        p_secret: String(token.refresh_token),
      });
      if (error) throw new Error('refresh-token storage failed: ' + error.message);
    }
    await vault(
      'youtube_unmapped_access_token',
      String(token.access_token),
      'Unmapped America YouTube short-lived access token',
    );
    await vault(
      'youtube_unmapped_access_token_expires_at',
      String(Date.now() + Number(token.expires_in || 3600) * 1000),
      'Unmapped America YouTube access-token expiry epoch ms',
    );
    diagnostic('credentials_stored', { refresh_token_stored: Boolean(token.refresh_token) });

    // Authentication recovery never changes publication authorization or resurrects old jobs.
    return new Response('YouTube connected for Unmapped America. The publishing queue and quality gates were preserved. Jo can now retry authorized work.\n', {
      status: 200,
      headers: {
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
        'Set-Cookie': '__Host-jo_youtube_state=; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=0',
      },
    });
  } catch (error) {
    diagnostic('unexpected_error', {
      message: String((error as any)?.message || error).slice(0, 220),
    });
    return reply('Connection repair encountered an internal error. The publishing jobs remain preserved.', 500);
  }
});
