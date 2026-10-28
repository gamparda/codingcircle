package kr.ruellyya.keepfall.signin

import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Google sign-in for Keepfall. Returns only the raw Google ID token; the game server verifies it
 * (signature, audience, expiry and the nonce it issued) and keeps nothing but the account subject.
 */
class KeepfallSignIn(godot: Godot) : GodotPlugin(godot) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun getPluginName() = "KeepfallSignIn"

    override fun getPluginSignals() = setOf(
        SignalInfo("sign_in_succeeded", String::class.java),
        SignalInfo("sign_in_failed", String::class.java, String::class.java),
        SignalInfo("signed_out"),
    )

    /**
     * Asks for a Google ID token for [webClientId] carrying [nonce]. Accounts that already signed in
     * to the game are offered first (and picked automatically when there is exactly one); otherwise
     * every Google account on the device is offered.
     */
    @UsedByGodot
    fun signIn(webClientId: String, nonce: String) {
        val activity = activity
        if (activity == null) {
            fail("no_activity", "")
            return
        }
        scope.launch {
            val manager = CredentialManager.create(activity)
            try {
                val token = try {
                    request(manager, webClientId, nonce, onlyAuthorized = true)
                } catch (_: NoCredentialException) {
                    request(manager, webClientId, nonce, onlyAuthorized = false)
                }
                runOnRenderThread { emitSignal("sign_in_succeeded", token) }
            } catch (_: GetCredentialCancellationException) {
                fail("cancelled", "")
            } catch (error: NoCredentialException) {
                fail("no_account", error.message ?: "")
            } catch (error: GetCredentialException) {
                fail("failed", error.type)
            } catch (error: GoogleIdTokenParsingException) {
                fail("bad_credential", error.message ?: "")
            } catch (error: IllegalStateException) {
                fail("bad_credential", error.message ?: "")
            }
        }
    }

    /** Forgets the automatic account choice, so the next sign-in shows the account list again. */
    @UsedByGodot
    fun signOut() {
        val activity = activity ?: return
        scope.launch {
            try {
                CredentialManager.create(activity).clearCredentialState(ClearCredentialStateRequest())
            } catch (_: Exception) {
                // Clearing the remembered choice is best effort; the game session is already gone.
            }
            runOnRenderThread { emitSignal("signed_out") }
        }
    }

    private suspend fun request(manager: CredentialManager, webClientId: String, nonce: String, onlyAuthorized: Boolean): String {
        val option = GetGoogleIdOption.Builder()
            .setServerClientId(webClientId)
            .setFilterByAuthorizedAccounts(onlyAuthorized)
            .setAutoSelectEnabled(onlyAuthorized)
            .setNonce(nonce)
            .build()
        val result = manager.getCredential(activity!!, GetCredentialRequest.Builder().addCredentialOption(option).build())
        val credential = result.credential
        check(credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) { "unexpected credential type" }
        return GoogleIdTokenCredential.createFrom(credential.data).idToken
    }

    private fun fail(code: String, detail: String) {
        runOnRenderThread { emitSignal("sign_in_failed", code, detail.take(200)) }
    }
}
