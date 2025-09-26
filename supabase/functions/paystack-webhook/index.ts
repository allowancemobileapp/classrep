import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import crypto from 'https://deno.land/std@0.177.0/node/crypto.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const paystackSecret = Deno.env.get('PAYSTACK_LIVE_SECRET_KEY')
    if (!paystackSecret) throw new Error('Paystack secret key is not set in environment variables.')

    const bodyText = await req.text()
    const signature = req.headers.get('x-paystack-signature')

    const hash = crypto.createHmac('sha512', paystackSecret).update(bodyText).digest('hex')
    if (hash !== signature) {
      return new Response(JSON.stringify({ error: 'Invalid signature' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const body = JSON.parse(bodyText)
    
    if (body.event === 'subscription.create') {
      const customerEmail = body.data.customer.email
      
      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
        { auth: { persistSession: false } }
      )

      const { data: userData, error: userError } = await supabaseAdmin
        .from('users')
        .select('id')
        .eq('email', customerEmail)
        .single()

      if (userError) throw new Error(`User with email ${customerEmail} not found. Details: ${userError.message}`)
      
      const { error: updateError } = await supabaseAdmin
        .from('users')
        .update({ is_plus: true })
        .eq('id', userData.id)
        
      if (updateError) throw new Error(`Failed to update user status: ${updateError.message}`)

      // --- ADD THIS BLOCK TO SEND THE PUSH NOTIFICATION ---
      try {
        await supabaseAdmin.functions.invoke('send-push-notification', {
          body: {
            userId: userData.id,
            title: 'Subscription Activated!',
            body: 'Welcome to Class-Rep Plus! You can now access all premium features.'
          }
        })
      } catch (invokeError) {
        // Log the error but don't fail the whole webhook, as the payment was successful.
        console.error('Failed to invoke send-push-notification function:', invokeError.message)
      }
      // --- END OF NEW BLOCK ---
    }
    
    return new Response(JSON.stringify({ status: 'ok' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    console.error(error)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})