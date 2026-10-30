package com.mdtaha.mykit.autofill

import android.app.AlertDialog
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.service.autofill.Dataset
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.RemoteViews
import android.widget.TextView
import androidx.fragment.app.FragmentActivity
import com.mdtaha.mykit.R
import com.mdtaha.mykit.vault.VaultKeyStore

/** Rows of the login list: section headers and logins. */
private sealed interface Row
private class Header(val text: String) : Row
private class Item(val login: VaultLogin) : Row
private object ShowAll : Row

/**
 * Opened from the "Unlock MyKit to fill" suggestion: asks for a fingerprint,
 * opens the vault, and lists logins (matches for this site / app first,
 * then a search over all). The chosen one is returned to Android, which
 * fills it. For apps, the choice is remembered (encrypted) for next time.
 */
class AutofillAuthActivity : FragmentActivity() {

    private var vaultKey: ByteArray? = null

    @Suppress("DEPRECATION")
    private fun <T> extra(name: String): T? = intent.getParcelableExtra(name)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Logins are on screen: no screenshots or recents preview.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        setResult(RESULT_CANCELED)

        if (!VaultKeyStore.hasKey(this)) {
            message(
                "Turn on fingerprint unlock",
                "To fill passwords from MyKit, open MyKit → Passwords → " +
                    "Settings and turn on \"Unlock with fingerprint\".",
            )
            return
        }
        try {
            VaultKeyStore.unlock(this, "Fill with MyKit") { outcome ->
                when (outcome) {
                    is VaultKeyStore.Outcome.Success -> showLogins(outcome.value as ByteArray)
                    VaultKeyStore.Outcome.Cancelled -> finish()
                    is VaultKeyStore.Outcome.Failed -> message("Couldn't unlock", outcome.message)
                }
            }
        } catch (e: VaultKeyStore.Invalidated) {
            message(
                "Fingerprint unlock was turned off",
                "Your fingerprints changed. Open MyKit → Passwords, unlock " +
                    "with your master password and turn fingerprint unlock on again.",
            )
        }
    }

    private fun showLogins(key: ByteArray) {
        vaultKey = key
        val packageName = intent.getStringExtra(EXTRA_PACKAGE) ?: ""
        val domain = intent.getStringExtra(EXTRA_DOMAIN)
        val fields = LoginFields(
            extra(EXTRA_USERNAME_ID),
            extra(EXTRA_PASSWORD_ID),
            packageName,
            domain,
        )
        val all = try {
            VaultReader.read(this, key)
        } catch (_: Exception) {
            message(
                "Couldn't open your passwords",
                "Open MyKit → Passwords once with your master password, then try again.",
            )
            return
        }
        if (all.isEmpty()) {
            message("No passwords yet", "Add logins in MyKit → Passwords first.")
            return
        }
        val links = AutofillLinks.read(this, key)
        val matches = VaultReader.matches(all, fields, links[packageName].orEmpty())
        val others = all.filter { it !in matches }.sortedBy { it.title.lowercase() }

        val where = domain?.let { VaultLogin.hostOf(it) }?.takeIf { it.isNotEmpty() }
            ?: appLabel(packageName)
        val adapter = LoginAdapter(matches, others, where)
        val dp = resources.displayMetrics.density
        val search = EditText(this).apply {
            hint = "Search all ${all.size} logins"
            setSingleLine()
            addTextChangedListener(object : TextWatcher {
                override fun afterTextChanged(s: Editable?) = adapter.filter(s.toString())
                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            })
        }
        val list = ListView(this).apply { this.adapter = adapter }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = (20 * dp).toInt()
            setPadding(pad, (8 * dp).toInt(), pad, 0)
            addView(search)
            addView(
                list,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    (360 * dp).toInt(),
                ),
            )
        }
        val dialog = AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("Fill login for $where")
            .setView(content)
            .setNegativeButton("Cancel") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .create()
        list.setOnItemClickListener { _, _, position, _ ->
            if (adapter.isShowAll(position)) {
                adapter.showAll()
                return@setOnItemClickListener
            }
            val login = adapter.loginAt(position) ?: return@setOnItemClickListener
            dialog.setOnDismissListener(null)
            dialog.dismiss()
            fill(fields, login)
        }
        dialog.setOnDismissListener { if (!isFinishing) finish() }
        dialog.show()
    }

    private fun fill(fields: LoginFields, login: VaultLogin) {
        val key = vaultKey ?: return finish()
        if (fields.webDomain.isNullOrEmpty() && fields.packageName.isNotEmpty()) {
            // Suggest this login for this app next time.
            AutofillLinks.link(this, key, fields.packageName, login.id)
        }
        val presentation = RemoteViews(packageName, R.layout.autofill_item).apply {
            setTextViewText(R.id.autofill_text, login.title)
        }
        val dataset = Dataset.Builder().apply {
            fields.username?.let { id ->
                if (login.username.isNotEmpty()) {
                    setValue(id, AutofillValue.forText(login.username), presentation)
                }
            }
            fields.password?.let { id ->
                setValue(id, AutofillValue.forText(login.password), presentation)
            }
        }.build()
        setResult(
            RESULT_OK,
            Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, dataset),
        )
        finish()
    }

    private fun message(title: String, text: String) {
        AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle(title)
            .setMessage(text)
            .setPositiveButton("OK") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }

    private fun appLabel(pkg: String): String = try {
        val info = packageManager.getApplicationInfo(pkg, 0)
        packageManager.getApplicationLabel(info).toString()
    } catch (_: Exception) {
        pkg.ifEmpty { "this app" }
    }

    override fun onDestroy() {
        vaultKey?.fill(0)
        vaultKey = null
        super.onDestroy()
    }

    /**
     * The logins for this site / app only; "Show other logins" (or a search)
     * opens up the rest. With no match, everything is listed under a note.
     */
    private inner class LoginAdapter(
        private val suggested: List<VaultLogin>,
        private val others: List<VaultLogin>,
        private val where: String,
    ) : BaseAdapter() {
        private var query = ""
        private var expanded = suggested.isEmpty()
        private var rows: List<Row> = build()

        private fun build(): List<Row> {
            val q = query.trim().lowercase()
            fun ok(l: VaultLogin) = q.isEmpty() || l.title.lowercase().contains(q) ||
                l.username.lowercase().contains(q) || l.host.contains(q)
            val s = suggested.filter(::ok)
            val o = if (expanded || q.isNotEmpty()) others.filter(::ok) else emptyList()
            return buildList {
                if (s.isNotEmpty()) {
                    add(Header("For $where"))
                    s.forEach { add(Item(it)) }
                }
                if (!expanded && q.isEmpty() && others.isNotEmpty()) add(ShowAll)
                if (o.isNotEmpty()) {
                    add(
                        Header(
                            if (suggested.isEmpty()) "No saved login for $where yet. Pick one:"
                            else "Other logins",
                        ),
                    )
                    o.forEach { add(Item(it)) }
                }
            }
        }

        fun filter(text: String) {
            query = text
            rows = build()
            notifyDataSetChanged()
        }

        fun showAll() {
            expanded = true
            rows = build()
            notifyDataSetChanged()
        }

        fun isShowAll(position: Int) = rows.getOrNull(position) === ShowAll

        fun loginAt(position: Int) = (rows.getOrNull(position) as? Item)?.login

        override fun getCount() = rows.size
        override fun getItem(position: Int) = rows[position]
        override fun getItemId(position: Int) = position.toLong()
        override fun isEnabled(position: Int) = rows[position] !is Header
        override fun areAllItemsEnabled() = false

        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val dp = resources.displayMetrics.density
            val view = TextView(this@AutofillAuthActivity).apply {
                val v = (10 * dp).toInt()
                setPadding((4 * dp).toInt(), v, (4 * dp).toInt(), v)
            }
            when (val row = rows[position]) {
                is Header -> view.apply {
                    text = row.text.uppercase()
                    textSize = 12f
                    setTypeface(typeface, Typeface.BOLD)
                    alpha = 0.6f
                }
                ShowAll -> view.apply {
                    text = "Show other logins (${others.size})"
                    textSize = 15f
                    alpha = 0.8f
                }
                is Item -> view.apply {
                    val sub = row.login.username.ifEmpty { row.login.host }
                    text = if (sub.isEmpty()) row.login.title else "${row.login.title}\n$sub"
                    textSize = 16f
                }
            }
            return view
        }
    }

    companion object {
        const val EXTRA_USERNAME_ID = "username_id"
        const val EXTRA_PASSWORD_ID = "password_id"
        const val EXTRA_PACKAGE = "package"
        const val EXTRA_DOMAIN = "domain"
    }
}
