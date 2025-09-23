// /supabase/functions/confirm-subscription-record/index.ts

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
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { persistSession: false } }
    )

    // 1. Get user from the request
    const authHeader = req.headers.get('Authorization')!
    const { data: { user } } = await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (!user) throw new Error('User not found.')

    // 2. Check for an active subscription record
    const { data, error, count } = await supabaseAdmin
      .from('subscriptions')
      .select('*', { count: 'exact' })
      .eq('user_id', user.id)
      .eq('status', 'active')

    if (error) {
      throw new Error(`Database error: ${error.message}`);
    }

    if (count === 1) {
      // Success! The record exists.
      return new Response(JSON.stringify({ status: 'success', message: 'Active subscription record confirmed.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    } else {
      // Failure or inconsistency.
      throw new Error('Verification failed: No active subscription record found for user.');
    }

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
