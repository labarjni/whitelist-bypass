package bypass.whitelist.ui

import android.app.AlertDialog
import android.app.Dialog
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.webkit.WebView
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.fragment.app.DialogFragment
import bypass.whitelist.R
import kotlinx.coroutines.*
import java.net.URL
import java.net.HttpURLConnection
import java.net.URLEncoder
import org.json.JSONObject

class MaxAuthDialogFragment : DialogFragment() {

    private lateinit var cookiesInput: EditText
    private lateinit var createButton: Button
    private lateinit var resultText: TextView
    private lateinit var errorText: TextView
    private var isLoading = false
    private var conferenceId: String? = null

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val view = LayoutInflater.from(requireContext())
            .inflate(R.layout.dialog_max_auth, null)

        cookiesInput = view.findViewById(R.id.cookiesInput)
        createButton = view.findViewById(R.id.createCallButton)
        resultText = view.findViewById(R.id.resultText)
        errorText = view.findViewById(R.id.errorText)

        createButton.setOnClickListener {
            if (!isLoading && cookiesInput.text.toString().trim().isNotEmpty()) {
                parseAndCreateCall()
            }
        }

        return AlertDialog.Builder(requireContext())
            .setTitle("MAX.ru Authorization")
            .setView(view)
            .setNegativeButton("Cancel") { _, _ -> }
            .create()
    }

    private fun parseAndCreateCall() {
        isLoading = true
        createButton.isEnabled = false
        createButton.text = "Creating..."
        errorText.text = ""
        resultText.text = ""
        conferenceId = null

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val jsonStr = cookiesInput.text.toString().trim()
                val json = JSONObject(jsonStr)

                // Extract __oneme_auth
                val onemeAuthStr = json.getString("__oneme_auth")
                val authJson = JSONObject(onemeAuthStr)
                val token = authJson.getString("token")
                val viewerId = authJson.getInt("viewerId")

                // Extract __oneme_calls_auth_token
                val callsAuthToken = json.getString("__oneme_calls_auth_token")

                // Extract device IDs
                val deviceId = json.optString("__oneme_device_id") ?: java.util.UUID.randomUUID().toString()
                val tracerDeviceId = json.optString("tracer-device-id") ?: java.util.UUID.randomUUID().toString()

                // Create the call
                val result = createMaxCall(token, viewerId, callsAuthToken, deviceId, tracerDeviceId)

                withContext(Dispatchers.Main) {
                    conferenceId = result
                    resultText.text = "Conference ID: $result"
                    createButton.text = "Create Call"
                    createButton.isEnabled = true
                    isLoading = false
                    
                    // Copy to clipboard
                    val clipboard = requireContext().getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    val clip = android.content.ClipData.newPlainText("conference_id", result)
                    clipboard.setPrimaryClip(clip)
                }

            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    errorText.text = "Error: ${e.message}"
                    createButton.text = "Create Call"
                    createButton.isEnabled = true
                    isLoading = false
                }
            }
        }
    }

    private fun createMaxCall(
        token: String,
        viewerId: Int,
        callsAuthToken: String,
        deviceId: String,
        tracerDeviceId: String
    ): String {
        // Build cookies string
        val onemeAuthJson = JSONObject().apply {
            put("token", token)
            put("viewerId", viewerId)
        }.toString()

        val cookies = listOf(
            "__oneme-persistent-cache-enabled=false",
            "__oneme_locale=en",
            "__oneme_auth=${URLEncoder.encode(onemeAuthJson, "UTF-8")}",
            "__server_config_overrides={}",
            "oneme_theme={\"colorScheme\":\"system\",\"colorTheme\":\"space\"}",
            "__oneme_device_id=$deviceId",
            "tracer-device-id=$tracerDeviceId",
            "__oneme_aside_width=393",
            "__oneme_informer={\"lastShowedBannerId\":null,\"banners\":{}}",
            "_okcls_uuid=\"${java.util.UUID.randomUUID()}\"",
            "__oneme_calls_auth_token=$callsAuthToken"
        ).joinToString("; ")

        // Generate random device ID for OK.ru
        val okDeviceId = (0L..9_000_000_000_000_000_000L).random().toString()

        // Prepare session data
        val sessionData = JSONObject().apply {
            put("version", 2)
            put("device_id", okDeviceId)
            put("client_version", "5.166")
            put("client_type", "WEB")
        }.toString()

        val apiURL = "https://calls.okcdn.ru/fb.do"

        // First request: auth.anonymLogin
        val authBody = listOf(
            "method=auth.anonymLogin",
            "session_data=${URLEncoder.encode(sessionData, "UTF-8")}",
            "application_key=O738Lb2eT6gYv2w8",
            "format=json"
        ).joinToString("&")

        val sessionKey = doAuthRequest(apiURL, authBody, cookies)

        // Second request: vchat.joinConversationByLink
        val joinBody = listOf(
            "method=vchat.joinConversationByLink",
            "session_key=$sessionKey",
            "application_key=O738Lb2eT6gYv2w8",
            "joinLink=",
            "anonymToken=$token",
            "isVideo=true",
            "isAudio=false",
            "mediaSettings=${URLEncoder.encode("{\"isAudioEnabled\":false,\"isVideoEnabled\":true,\"isScreenSharingEnabled\":false}", "UTF-8")}",
            "format=json"
        ).joinToString("&")

        return doJoinRequest(apiURL, joinBody, cookies)
    }

    private fun doAuthRequest(url: String, body: String, cookies: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36")
            connection.setRequestProperty("Origin", "https://web.max.ru")
            connection.setRequestProperty("Referer", "https://web.max.ru/")
            connection.setRequestProperty("Cookie", cookies)
            connection.doOutput = true
            connection.connectTimeout = 15000
            connection.readTimeout = 15000

            connection.outputStream.write(body.toByteArray())

            val responseCode = connection.responseCode
            if (responseCode != 200) {
                throw Exception("Auth request failed: $responseCode")
            }

            val response = connection.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(response)
            
            val sessionKey = json.optString("session_key")
            if (sessionKey.isEmpty()) {
                throw Exception("Missing session_key in auth response")
            }
            
            return sessionKey
        } finally {
            connection.disconnect()
        }
    }

    private fun doJoinRequest(url: String, body: String, cookies: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36")
            connection.setRequestProperty("Origin", "https://web.max.ru")
            connection.setRequestProperty("Referer", "https://web.max.ru/")
            connection.setRequestProperty("Cookie", cookies)
            connection.doOutput = true
            connection.connectTimeout = 15000
            connection.readTimeout = 15000

            connection.outputStream.write(body.toByteArray())

            val responseCode = connection.responseCode
            if (responseCode != 200) {
                throw Exception("Join request failed: $responseCode")
            }

            val response = connection.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(response)
            
            val conferenceId = json.optString("id")
            if (conferenceId.isEmpty()) {
                throw Exception("Missing conference ID in join response")
            }
            
            return conferenceId
        } finally {
            connection.disconnect()
        }
    }
}
