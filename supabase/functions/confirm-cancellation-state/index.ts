// /supabase/functions/confirm-cancellation-state/index.ts

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

    // 2. Verify the user's is_plus status is false
    const { data: userData, error: userError } = await supabaseAdmin
      .from('users')
      .select('is_plus')
      .eq('id', user.id)
      .single()

    if (userError) throw new Error(`Could not fetch user profile: ${userError.message}`);
    if (userData.is_plus === true) {
      throw new Error('Verification failed: User is_plus flag is still true.');
    }

    // 3. Verify no active subscription record exists
    const { count } = await supabaseAdmin
      .from('subscriptions')
      .select('*', { count: 'exact', head: true }) // head:true is more efficient
      .eq('user_id', user.id)
      .eq('status', 'active')

    if (count !== 0) {
      throw new Error(`Verification failed: Found ${count} active subscription records for the user.`);
    }

    // If both checks pass, it's a success
    return new Response(JSON.stringify({ status: 'success', message: 'User cancellation state confirmed.' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
