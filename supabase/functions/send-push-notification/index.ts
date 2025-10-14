import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { create } from 'https://deno.land/x/djwt@v2.2/mod.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};

// Helper function to get a temporary Google OAuth2 access token
async function getAccessToken(serviceAccount) {
  const jwt = await create({
    alg: 'RS256',
    typ: 'JWT'
  }, {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: Math.floor(Date.now() / 1000) + 3600,
    iat: Math.floor(Date.now() / 1000)
  }, serviceAccount.private_key);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body: new URLSearchParams({
      'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      'assertion': jwt
    })
  });
  const data = await response.json();
  return data.access_token;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const payload = await req.json();
    let recipientUserId, actorUserId, notificationType, notificationPayload, title, body;

    // Check if this is a webhook payload (from notifications insert)
    if (payload.record) {
      const notification = payload.record;
      recipientUserId = notification.recipient_user_id;
      actorUserId = notification.actor_user_id;
      notificationType = notification.type;
      notificationPayload = notification.payload || {};

      // Fetch actor's username for personalization
      const supabaseAdmin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
        auth: { persistSession: false }
      });
      const { data: actorData, error: actorError } = await supabaseAdmin
        .from('users')
        .select('username')
        .eq('id', actorUserId)
        .single();

      if (actorError) {
        console.error('Error fetching actor:', actorError.message);
      }

      const actorUsername = actorData?.username || 'Someone';

      // Generate title and body based on type
      switch (notificationType) {
        case 'subscription':
          title = 'New Subscriber!';
          body = `${actorUsername} has subscribed to your timetable.`;
          break;
        case 'new_comment':
          title = 'New Comment';
          body = `${actorUsername} commented on your event.`;
          break;
        case 'new_gist':
          title = 'New Gist';
          body = `${actorUsername} posted a new gist.`;
          break;
        case 'new_event':
          title = 'New Event';
          body = `${actorUsername} added a new event: ${notificationPayload.title || ''}.`;
          break;
        case 'event_reminder':
          title = 'Event Reminder';
          body = `Reminder for ${notificationPayload.event_title || 'your event'} at ${notificationPayload.event_start_time || ''}.`;
          break;
        // Add more cases as needed (e.g., for chat messages if you want to route them here)
        default:
          console.log('Unknown notification type:', notificationType);
          return new Response(JSON.stringify({ message: 'Unknown type' }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200
          });
      }
    } else {
      // Fallback for manual/direct calls (e.g., your existing chat pushes)
      ({ userId: recipientUserId, title, body } = payload);
      if (!recipientUserId || !title || !body) {
        throw new Error('userId, title, and body are required for manual calls.');
      }
    }

    // Fetch recipient's FCM token
    const supabaseAdmin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
      auth: { persistSession: false }
    });
    const { data: userData, error: userError } = await supabaseAdmin
      .from('users')
      .select('fcm_token')
      .eq('id', recipientUserId)
      .single();

    if (userError) throw new Error(`User not found: ${userError.message}`);
    if (!userData.fcm_token) {
      console.log(`User ${recipientUserId} does not have an FCM token. Skipping notification.`);
      return new Response(JSON.stringify({ message: 'User has no FCM token.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200
      });
    }

    // Send the push via FCM v1
    const serviceAccountJson = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON');
    if (!serviceAccountJson) throw new Error('Service account JSON secret is not set.');
    const serviceAccount = JSON.parse(serviceAccountJson);
    const projectId = serviceAccount.project_id;
    const accessToken = await getAccessToken(serviceAccount);
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    const messagePayload = {
      message: {
        token: userData.fcm_token,
        notification: { title, body },
        data: notificationPayload // Send the full payload for app handling (e.g., deep links)
      }
    };

    const response = await fetch(fcmUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(messagePayload)
    });

    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(`FCM API v1 error: ${response.status} ${errorBody}`);
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200
    });
  } catch (error) {
    console.error(error.message);
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400
    });
  }
});