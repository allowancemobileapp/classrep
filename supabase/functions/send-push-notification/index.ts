import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { userId, title, body } = await req.json()
    if (!userId || !title || !body) {
      throw new Error('userId, title, and body are required.')
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { persistSession: false } }
    )

    // Get the user's FCM token from the database
    const { data: userData, error: userError } = await supabaseAdmin
      .from('users')
      .select('fcm_token')
      .eq('id', userId)
      .single()

    if (userError) throw new Error(`User not found: ${userError.message}`)
    if (!userData.fcm_token) {
      console.log(`User ${userId} does not have an FCM token. Skipping notification.`);
      return new Response(JSON.stringify({ message: 'User has no FCM token.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const fcmServerKey = Deno.env.get('FCM_SERVER_KEY');
    if (!fcmServerKey) throw new Error('FCM server key is not set.')

    // Construct the FCM payload
    const message = {
      to: userData.fcm_token,
      notification: {
        title: title,
        body: body,
      },
    }

    // Send the request to FCM
    const response = await fetch('https://fcm.googleapis.com/fcm/send', {
      method: 'POST',
      headers: {
        'Authorization': `key=${fcmServerKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(message),
    })

    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(`FCM API error: ${response.status} ${errorBody}`);
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error(error.message)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})