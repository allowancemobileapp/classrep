// /supabase/functions/cancel-paystack-subscription/index.ts

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

    const authHeader = req.headers.get('Authorization')!
    const { data: { user } } = await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (!user) throw new Error('User not found.')

    const { data: subData, error: subError } = await supabaseAdmin
      .from('subscriptions')
      .select('provider_subscription_id')
      .eq('user_id', user.id)
      .eq('status', 'active')
      .single()
    
    if (subError || !subData) {
      await supabaseAdmin.from('users').update({ is_plus: false }).eq('id', user.id);
      return new Response(JSON.stringify({ message: 'User state synchronized.' }));
    }

    const paystackSecret = Deno.env.get('PAYSTACK_SECRET_KEY')
    if (!paystackSecret) throw new Error('Paystack secret not set.')

    const subscriptionId = subData.provider_subscription_id;
    
    // This is the call that was failing, which you will now handle manually.
    const paystackResponse = await fetch(`https://api.paystack.co/subscription/${subscriptionId}`, {
      method: 'DELETE',
      headers: { 'Authorization': `Bearer ${paystackSecret}` },
    })

    if (!paystackResponse.ok) {
        const errorText = await paystackResponse.text();
        throw new Error(`Paystack API error: ${errorText || 'Empty response'}`);
    }

    await supabaseAdmin.from('users').update({ is_plus: false }).eq('id', user.id);
    await supabaseAdmin.from('subscriptions').delete().eq('user_id', user.id);

    return new Response(JSON.stringify({ message: 'Subscription cancelled successfully.' }))

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }
})

