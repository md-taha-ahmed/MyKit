package com.mdtaha.mykit.autofill

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** A saved login, as autofill needs it. */
class VaultLogin(
    val id: String,
    val title: String,
    val username: String,
    val password: String,
    val url: String,
) {
    /** "github.com" from the URL. */
    val host: String = hostOf(url)

    companion object {
        fun hostOf(url: String): String {
            val raw = url.trim().lowercase()
            if (raw.isEmpty()) return ""
            val withScheme = if (raw.contains("://")) raw else "https://$raw"
            val host = try {
                java.net.URI(withScheme).host ?: ""
            } catch (_: Exception) {
                ""
            }
            return host.removePrefix("www.").removePrefix("m.")
        }
    }
}

/**
 * Reads the Passwords vault written by the Flutter app (`vault.v1` in
 * Flutter's preferences; see `vault_crypto.dart`) with the vault key.
 */
object VaultReader {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val VAULT_KEY = "flutter.vault.v1"
    private val DATA_AAD = "mykit-vault-v1:data".toByteArray()

    fun hasVault(context: Context) =
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE).contains(VAULT_KEY)

    /** All logins with a password. Throws if [vaultKey] doesn't open the vault. */
    fun read(context: Context, vaultKey: ByteArray): List<VaultLogin> {
        val raw = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString(VAULT_KEY, null) ?: return emptyList()
        val data = JSONObject(raw).getJSONObject("data")
        val json = String(Crypto.open(vaultKey, data, DATA_AAD))
        val entries = JSONArray(json)
        return (0 until entries.length()).map { entries.getJSONObject(it) }
            .filter { it.optString("password").isNotEmpty() }
            .map {
                VaultLogin(
                    id = it.getString("id"),
                    title = it.optString("title"),
                    username = it.optString("username"),
                    password = it.optString("password"),
                    url = it.optString("url"),
                )
            }
    }

    /**
     * Logins for this screen, best first: same site (web), or apps linked
     * before / whose package name contains the site's name.
     */
    fun matches(
        logins: List<VaultLogin>,
        fields: LoginFields,
        linkedIds: Set<String>,
    ): List<VaultLogin> {
        val domain = fields.webDomain?.let { VaultLogin.hostOf(it) }
        if (!domain.isNullOrEmpty()) {
            val site = siteOf(domain)
            return logins.filter { it.host.isNotEmpty() && siteOf(it.host) == site }
        }
        val pkg = fields.packageName.lowercase()
        val linked = logins.filter { it.id in linkedIds }
        val guessed = logins.filter { login ->
            login.id !in linkedIds && siteName(login.host).let { it.length >= 3 && pkg.contains(it) }
        }
        return linked + guessed
    }

    /** "accounts.google.com" → "google.com"; "bbc.co.uk" stays. */
    fun siteOf(host: String): String {
        val parts = host.split('.').filter { it.isNotEmpty() }
        if (parts.size <= 2) return host
        val secondLevel = setOf("co", "com", "org", "net", "gov", "edu", "ac", "or", "ne")
        val keep = if (parts[parts.size - 2] in secondLevel && parts.last().length == 2) 3 else 2
        return parts.takeLast(keep).joinToString(".")
    }

    /** "github.com" → "github". */
    private fun siteName(host: String) = siteOf(host).substringBefore('.')
}

/**
 * Which logins were used for which apps, so they're suggested next time.
 * Encrypted with the vault key (it reveals which apps you have accounts in);
 * included in backups, where the same vault key still opens it.
 */
object AutofillLinks {
    private const val PREFS = "autofill_links"
    private const val KEY = "links"
    private val AAD = "mykit-vault-v1:autofill-links".toByteArray()

    fun read(context: Context, vaultKey: ByteArray): MutableMap<String, MutableSet<String>> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            ?: return mutableMapOf()
        return try {
            val json = JSONObject(String(Crypto.open(vaultKey, JSONObject(raw), AAD)))
            json.keys().asSequence().associateWith { pkg ->
                val ids = json.getJSONArray(pkg)
                (0 until ids.length()).map { ids.getString(it) }.toMutableSet()
            }.toMutableMap()
        } catch (_: Exception) {
            mutableMapOf() // e.g. the vault was replaced
        }
    }

    fun link(context: Context, vaultKey: ByteArray, packageName: String, loginId: String) {
        val links = read(context, vaultKey)
        links.getOrPut(packageName) { mutableSetOf() }.add(loginId)
        val json = JSONObject()
        links.forEach { (pkg, ids) -> json.put(pkg, JSONArray(ids.toList())) }
        val sealed = Crypto.seal(vaultKey, json.toString().toByteArray(), AAD)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY, sealed.toString()).apply()
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }
}

/**
 * AES-256-GCM boxes in the app's format: `{"n": nonce, "c": ciphertext,
 * "m": 16-byte tag}`, base64 (Dart's `cryptography` keeps the tag apart;
 * Java wants it appended).
 */
private object Crypto {
    private val decoder = Base64.getDecoder()
    private val encoder = Base64.getEncoder()

    fun open(key: ByteArray, box: JSONObject, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(key, "AES"),
            GCMParameterSpec(128, decoder.decode(box.getString("n"))),
        )
        cipher.updateAAD(aad)
        return cipher.doFinal(decoder.decode(box.getString("c")) + decoder.decode(box.getString("m")))
    }

    fun seal(key: ByteArray, plain: ByteArray, aad: ByteArray): JSONObject {
        val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(aad)
        val out = cipher.doFinal(plain)
        return JSONObject()
            .put("n", encoder.encodeToString(nonce))
            .put("c", encoder.encodeToString(out.copyOfRange(0, out.size - 16)))
            .put("m", encoder.encodeToString(out.copyOfRange(out.size - 16, out.size)))
    }
}
