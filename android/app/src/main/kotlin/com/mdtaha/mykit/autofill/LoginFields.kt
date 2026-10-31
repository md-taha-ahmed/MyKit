package com.mdtaha.mykit.autofill

import android.app.assist.AssistStructure
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId

/**
 * The login fields on a screen (in an app or a web page in a browser), and
 * where they are: the app's package and, for web pages, the site's domain.
 */
class LoginFields(
    val username: AutofillId?,
    val password: AutofillId?,
    val packageName: String,
    val webDomain: String?,
) {
    val isEmpty get() = username == null && password == null
    val ids get() = listOfNotNull(username, password)

    companion object {
        private val passwordWords = listOf("password", "passwd", "pass", "pwd", "pin", "كلمة")
        private val usernameWords = listOf(
            "user", "email", "e-mail", "mail", "login", "account", "phone",
            "mobile", "identifier", "username", "اسم", "البريد",
        )

        private class Candidate(val id: AutofillId, val kind: Kind, val order: Int)
        private enum class Kind { USERNAME, PASSWORD, TEXT }

        fun parse(structure: AssistStructure): LoginFields {
            val candidates = mutableListOf<Candidate>()
            var webDomain: String? = null
            var order = 0

            fun visit(node: AssistStructure.ViewNode) {
                if (webDomain == null && !node.webDomain.isNullOrBlank()) {
                    webDomain = node.webDomain
                }
                val id = node.autofillId
                if (id != null && node.autofillType == View.AUTOFILL_TYPE_TEXT &&
                    node.visibility == View.VISIBLE
                ) {
                    classify(node)?.let { candidates += Candidate(id, it, order++) }
                }
                for (i in 0 until node.childCount) visit(node.getChildAt(i))
            }

            for (i in 0 until structure.windowNodeCount) {
                visit(structure.getWindowNodeAt(i).rootViewNode)
            }

            val password = candidates.firstOrNull { it.kind == Kind.PASSWORD }
            // The username: one marked as such, preferably just before the
            // password; otherwise the plain text field right before it.
            val username = candidates
                .filter { it.kind == Kind.USERNAME }
                .let { users ->
                    if (password == null) users.firstOrNull()
                    else users.lastOrNull { it.order < password.order } ?: users.firstOrNull()
                }
                ?: password?.let { p ->
                    candidates.lastOrNull { it.kind == Kind.TEXT && it.order < p.order }
                }

            return LoginFields(
                username = username?.id,
                password = password?.id,
                packageName = structure.activityComponent?.packageName ?: "",
                webDomain = webDomain,
            )
        }

        private fun classify(node: AssistStructure.ViewNode): Kind? {
            // 1. Explicit autofill hints (the app or page says what it is).
            node.autofillHints?.forEach { hint ->
                val h = hint.lowercase()
                if (h.contains("password") && !h.contains("new")) return Kind.PASSWORD
                if (h.contains("username") || h.contains("email") || h.contains("phone")) {
                    return Kind.USERNAME
                }
            }
            // 2. Web pages: the <input> type / name / autocomplete.
            node.htmlInfo?.let { html ->
                if (!html.tag.equals("input", ignoreCase = true)) return null
                val attrs = html.attributes?.associate {
                    (it.first ?: "").lowercase() to (it.second ?: "").lowercase()
                }.orEmpty()
                val type = attrs["type"] ?: "text"
                val autocomplete = attrs["autocomplete"] ?: ""
                return when {
                    type == "password" -> Kind.PASSWORD
                    type in setOf("hidden", "submit", "button", "checkbox", "radio", "search") -> null
                    autocomplete.contains("username") || autocomplete.contains("email") ||
                        type == "email" || type == "tel" -> Kind.USERNAME
                    usernameWords.any { w -> listOfNotNull(attrs["name"], attrs["id"]).any { it.contains(w) } } ->
                        Kind.USERNAME
                    type == "text" -> Kind.TEXT
                    else -> null
                }
            }
            // 3. Native views: the input type, then id / hint text.
            val inputType = node.inputType
            val variation = inputType and InputType.TYPE_MASK_VARIATION
            val textClass = inputType and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_TEXT
            if (textClass && variation in setOf(
                    InputType.TYPE_TEXT_VARIATION_PASSWORD,
                    InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
                    InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
                )
            ) {
                return Kind.PASSWORD
            }
            if (inputType and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_NUMBER &&
                variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
            ) {
                return Kind.PASSWORD
            }
            if (textClass && variation in setOf(
                    InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                    InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS,
                )
            ) {
                return Kind.USERNAME
            }
            val words = listOfNotNull(node.idEntry, node.hint, node.contentDescription?.toString())
                .joinToString(" ").lowercase()
            return when {
                passwordWords.any { words.contains(it) } && !words.contains("forgot") -> Kind.PASSWORD
                usernameWords.any { words.contains(it) } -> Kind.USERNAME
                node.className?.contains("EditText") == true || inputType != 0 -> Kind.TEXT
                else -> null
            }
        }
    }
}
