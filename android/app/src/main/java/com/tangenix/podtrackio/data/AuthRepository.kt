package com.tangenix.podtrackio.data

import android.net.Uri
import com.google.gson.JsonObject
import com.tangenix.podtrackio.BuildConfig
import com.tangenix.podtrackio.domain.AuthSession
import com.tangenix.podtrackio.domain.UserProfile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit

data class AuthState(
    val restoring: Boolean = true,
    val session: AuthSession? = null,
    val profile: UserProfile? = null,
    val error: String? = null,
) {
    val isAuthenticated get() = session != null && profile != null
}

class AuthRepository(
    private val secureStore: SecureStore,
    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build(),
) {
    private val refreshMutex = Mutex()
    private val _state = MutableStateFlow(AuthState())
    val state: StateFlow<AuthState> = _state.asStateFlow()

    val projectUrl get() = BuildConfig.SUPABASE_URL.trimEnd('/')
    private val anonKey get() = BuildConfig.SUPABASE_ANON_KEY

    suspend fun restore() {
        val access = secureStore.get(SecureStore.ACCESS_TOKEN)
        val refresh = secureStore.get(SecureStore.REFRESH_TOKEN)
        if (access.isNullOrBlank() || refresh.isNullOrBlank()) {
            _state.value = AuthState(restoring = false)
            return
        }
        _state.value = AuthState(restoring = true, session = AuthSession(access, refresh))
        if (!refresh()) signOut(localOnly = true)
    }

    fun oauthUri(provider: String): Uri {
        requireConfigured()
        val redirect = URLEncoder.encode("podtrackio://auth-callback", StandardCharsets.UTF_8.name())
        return Uri.parse("$projectUrl/auth/v1/authorize?provider=$provider&redirect_to=$redirect")
    }

    suspend fun handleCallback(uri: Uri): Boolean {
        if (uri.scheme != "podtrackio" || uri.host != "auth-callback") return false
        val params = buildMap {
            uri.fragment?.split('&')?.forEach { pair ->
                val values = pair.split('=', limit = 2)
                if (values.size == 2) put(values[0], Uri.decode(values[1]))
            }
            uri.queryParameterNames.forEach { name -> uri.getQueryParameter(name)?.let { put(name, it) } }
        }
        params["error_description"]?.let {
            _state.value = _state.value.copy(restoring = false, error = it.replace('+', ' '))
            return false
        }
        val access = params["access_token"] ?: return false
        val refresh = params["refresh_token"] ?: return false
        store(AuthSession(access, refresh))
        return fetchProfile()
    }

    suspend fun refresh(): Boolean = refreshMutex.withLock {
        val current = _state.value.session ?: return@withLock false
        runCatching {
            requireConfigured()
            val body = JsonObject().apply { addProperty("refresh_token", current.refreshToken) }
            val request = Request.Builder()
                .url("$projectUrl/auth/v1/token?grant_type=refresh_token")
                .header("apikey", anonKey)
                .header("Authorization", "Bearer $anonKey")
                .post(Json.gson.toJson(body).toRequestBody(JSON_MEDIA))
                .build()
            val response = withContext(Dispatchers.IO) { http.newCall(request).execute() }
            response.use {
                check(it.isSuccessful) { "Session refresh failed (${it.code})" }
                val payload = Json.gson.fromJson(it.body?.string(), JsonObject::class.java)
                val session = AuthSession(payload["access_token"].asString, payload["refresh_token"].asString)
                store(session)
            }
            fetchProfile()
        }.getOrElse {
            _state.value = AuthState(restoring = false, error = "Your session expired. Please sign in again.")
            false
        }
    }

    suspend fun fetchProfile(): Boolean = runCatching {
        val session = _state.value.session ?: error("No session")
        val request = Request.Builder()
            .url("$projectUrl/auth/v1/user")
            .header("apikey", anonKey)
            .header("Authorization", "Bearer ${session.accessToken}")
            .build()
        val response = withContext(Dispatchers.IO) { http.newCall(request).execute() }
        response.use {
            if (it.code == 401) return refresh()
            check(it.isSuccessful) { "Profile request failed (${it.code})" }
            val json = Json.gson.fromJson(it.body?.string(), JsonObject::class.java)
            val metadata = json.getAsJsonObject("user_metadata")
            val profile = UserProfile(
                id = json["id"].asString,
                email = json.get("email")?.takeUnless(JsonElementExtensions::isNull)?.asString,
                displayName = metadata?.firstString("full_name", "name"),
                avatarUrl = metadata?.firstString("avatar_url", "picture"),
            )
            _state.value = AuthState(restoring = false, session = session, profile = profile)
            true
        }
    }.getOrElse {
        _state.value = _state.value.copy(restoring = false, error = it.message ?: "Could not restore your account.")
        false
    }

    suspend fun signOut(localOnly: Boolean = false) {
        val session = _state.value.session
        if (!localOnly && session != null) {
            val request = Request.Builder().url("$projectUrl/auth/v1/logout")
                .header("apikey", anonKey)
                .header("Authorization", "Bearer ${session.accessToken}")
                .post(ByteArray(0).toRequestBody(null)).build()
            withContext(Dispatchers.IO) { runCatching { http.newCall(request).execute().close() } }
        }
        secureStore.remove(SecureStore.ACCESS_TOKEN, SecureStore.REFRESH_TOKEN)
        _state.value = AuthState(restoring = false)
    }

    fun clearError() { _state.value = _state.value.copy(error = null) }

    private fun store(session: AuthSession) {
        secureStore.put(SecureStore.ACCESS_TOKEN, session.accessToken)
        secureStore.put(SecureStore.REFRESH_TOKEN, session.refreshToken)
        _state.value = AuthState(restoring = true, session = session)
    }

    private fun requireConfigured() {
        check(projectUrl.startsWith("https://") && anonKey.isNotBlank()) {
            "Supabase is not configured. Add PODTRACKIO_SUPABASE_URL and PODTRACKIO_SUPABASE_ANON_KEY to local.properties."
        }
    }

    private fun JsonObject.firstString(vararg names: String): String? = names.firstNotNullOfOrNull { name ->
        get(name)?.takeUnless { it.isJsonNull }?.asString?.takeIf(String::isNotBlank)
    }

    private object JsonElementExtensions {
        fun isNull(element: com.google.gson.JsonElement) = element.isJsonNull
    }

    companion object { private val JSON_MEDIA = "application/json".toMediaType() }
}
