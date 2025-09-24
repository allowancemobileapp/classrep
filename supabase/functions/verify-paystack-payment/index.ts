// /supabase/functions/verify-paystack-payment/index.ts

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
    const { reference } = await req.json()
    if (!reference) throw new Error('Payment reference is missing.')

    const paystackSecret = Deno.env.get('PAYSTACK_SECRET_KEY')
    if (!paystackSecret) throw new Error('Paystack secret key is not set.')

    const verifyRes = await fetch(`https://api.paystack.co/transaction/verify/${reference}`, {
      headers: { 'Authorization': `Bearer ${paystackSecret}` },
    })
    
    if (!verifyRes.ok) {
        const errorBody = await verifyRes.text();
        throw new Error(`Failed to verify transaction with Paystack: ${errorBody}`)
    }
    
    const verifyBody = await verifyRes.json()
    const verifyData = verifyBody.data
    
    if (verifyData.status !== 'success') {
        throw new Error(`Payment was not successful. Status: ${verifyData.status}`)
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { persistSession: false } }
    )

    const customerEmail = verifyData.customer.email
    const { data: userData, error: userError } = await supabaseAdmin.from('users').select('id').eq('email', customerEmail).single()
    if (userError || !userData) {
        throw new Error(`User with email ${customerEmail} not found.`)
    }

    await supabaseAdmin.from('users').update({ is_plus: true }).eq('id', userData.id)

    const authorization = verifyData.authorization;
    if (authorization && authorization.authorization_code) {
      const { error: upsertError } = await supabaseAdmin.from('subscriptions').upsert({
        user_id: userData.id,
        provider: 'paystack',
        status: 'active',
        plan_code: verifyData.plan,
        provider_subscription_id: authorization.authorization_code,
      }, { onConflict: 'user_id' });

      if (upsertError) {
          throw new Error(`Failed to save subscription record: ${upsertError.message}`);
      }
    }

    return new Response(JSON.stringify({ 
        status: 'success', 
        message: 'User status updated and subscription recorded.' 
    }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
    })

  } catch (error) {
    console.error('Verification Error:', error.message);
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})