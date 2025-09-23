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

    // 1. Call Paystack to verify the transaction
    const paystackResponse = await fetch(`https://api.paystack.co/transaction/verify/${reference}`, {
      headers: { 'Authorization': `Bearer ${paystackSecret}` },
    })

    if (!paystackResponse.ok) {
      throw new Error('Failed to verify transaction with Paystack.')
    }

    const paystackData = await paystackResponse.json()

    // 2. Check if the payment was successful
    if (paystackData.data.status === 'success') {
      const customerEmail = paystackData.data.customer.email

      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
        { auth: { persistSession: false } }
      )

      // 3. Find the user by email
      const { data: userData, error: userError } = await supabaseAdmin
        .from('users')
        .select('id')
        .eq('email', customerEmail)
        .single()

      if (userError) throw new Error(`User not found: ${userError.message}`)

      // 4. Update the user's profile to is_plus = true
      const { error: updateError } = await supabaseAdmin
        .from('users')
        .update({ is_plus: true })
        .eq('id', userData.id)

      if (updateError) throw new Error(`Failed to update user: ${updateError.message}`)

      return new Response(JSON.stringify({ status: 'success', message: 'User status updated.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    } else {
      throw new Error('Payment was not successful.')
    }
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})