package site.wingspot.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer

class AuthTests {
    private fun withServer(block: (MockWebServer, SupabaseAuth) -> Unit) {
        MockWebServer().use { server ->
            server.start()
            block(server, SupabaseAuth(server.url("/").toString(), "sb_publishable_test"))
        }
    }

    @Test
    fun theChallengeIsTheSha256OfTheVerifier() {
        // The example from RFC 7636, appendix B.
        assertEquals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", Pkce.challengeFor("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
        val a = Pkce.create()
        val b = Pkce.create()
        assert(a.verifier != b.verifier)
        assertEquals(Pkce.challengeFor(a.verifier), a.challenge)
    }

    @Test
    fun askingForALinkSendsTheChallengeTheRedirectAndTheLanguage() = withServer { server, auth ->
        server.enqueue(MockResponse.Builder().code(200).body("{}").build())
        val pkce = Pkce.create()
        runBlocking { auth.sendSignInLink("anna@example.test", "de", pkce) }
        val request = server.takeRequest()
        assertEquals("/auth/v1/otp?redirect_to=wingspot%3A%2F%2Fauth-callback", request.url.encodedPath + "?" + request.url.encodedQuery)
        assertEquals("sb_publishable_test", request.headers["apikey"])
        val body = Json.parseToJsonElement(request.body!!.utf8()).jsonObject
        assertEquals("anna@example.test", body["email"]!!.jsonPrimitive.content)
        assertEquals(pkce.challenge, body["code_challenge"]!!.jsonPrimitive.content)
        assertEquals("s256", body["code_challenge_method"]!!.jsonPrimitive.content)
        assertEquals("de", body["data"]!!.jsonObject["language"]!!.jsonPrimitive.content)
    }

    @Test
    fun theLinkCodeIsTradedForASession() = withServer { server, auth ->
        server.enqueue(
            MockResponse.Builder().code(200).body(
                """{"access_token":"a","refresh_token":"r","expires_in":3600,"token_type":"bearer","user":{"id":"u1","email":"anna@example.test","aud":"x"}}""",
            ).build(),
        )
        val pkce = Pkce.create()
        val session = runBlocking { auth.completeSignIn("wingspot://auth-callback?code=abc123", pkce) }
        assertEquals("u1", session.user.id)
        assertEquals("a", session.accessToken)
        val request = server.takeRequest()
        assertEquals("pkce", request.url.queryParameter("grant_type"))
        val body = Json.parseToJsonElement(request.body!!.utf8()).jsonObject
        assertEquals("abc123", body["auth_code"]!!.jsonPrimitive.content)
        assertEquals(pkce.verifier, body["code_verifier"]!!.jsonPrimitive.content)
    }

    @Test
    fun aLinkWithoutACodeFailsWithoutAnyRequest() = withServer { server, auth ->
        assertFailsWith<AuthException.InvalidLink> { runBlocking { auth.completeSignIn("wingspot://auth-callback", Pkce.create()) } }
        assertFailsWith<AuthException.InvalidLink> { runBlocking { auth.completeSignIn("wingspot://auth-callback?error=access_denied", Pkce.create()) } }
        assertEquals(0, server.requestCount)
    }

    @Test
    fun serverAnswersAreMapped() = withServer { server, auth ->
        server.enqueue(MockResponse.Builder().code(429).body("{}").build())
        assertFailsWith<AuthException.TooManyRequests> { runBlocking { auth.sendSignInLink("a@b.c", null, Pkce.create()) } }
        server.enqueue(MockResponse.Builder().code(422).body("""{"msg":"Unable to validate email address"}""").build())
        assertFailsWith<AuthException.InvalidEmail> { runBlocking { auth.sendSignInLink("nope", null, Pkce.create()) } }
        server.enqueue(MockResponse.Builder().code(400).body("""{"error_code":"flow_state_not_found"}""").build())
        assertFailsWith<AuthException.InvalidLink> { runBlocking { auth.completeSignIn("wingspot://auth-callback?code=x", Pkce.create()) } }
        server.enqueue(MockResponse.Builder().code(500).body("oops").build())
        assertFailsWith<AuthException.Unknown> { runBlocking { auth.sendSignInLink("a@b.c", null, Pkce.create()) } }
    }

    @Test
    fun queryParametersAreReadSafely() {
        assertEquals("a b", SupabaseAuth.queryParameter("wingspot://auth-callback?code=a%20b&x=1", "code"))
        assertNull(SupabaseAuth.queryParameter("wingspot://auth-callback?x=1", "code"))
        assertNull(SupabaseAuth.queryParameter("not a url", "code"))
    }
}
