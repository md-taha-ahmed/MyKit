package com.mdtaha.mykit.autofill

import android.app.PendingIntent
import android.content.Intent
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import com.mdtaha.mykit.AppLanguage
import com.mdtaha.mykit.R
import com.mdtaha.mykit.vault.VaultKeyStore

/**
 * MyKit as Android's autofill service (Settings → Passwords & accounts →
 * Autofill service). On a login form it offers one suggestion, "Unlock
 * MyKit", that opens [AutofillAuthActivity]: fingerprint, pick a login, and
 * the fields are filled. The vault itself is only opened there, after the
 * fingerprint check.
 */
class MyKitAutofillService : AutofillService() {

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }
        val fields = LoginFields.parse(structure)
        // Nothing to fill, our own app, or no vault / no fingerprint unlock.
        if (fields.isEmpty || fields.packageName == packageName ||
            !VaultReader.hasVault(this)
        ) {
            callback.onSuccess(null)
            return
        }

        val label = if (VaultKeyStore.hasKey(this)) {
            AppLanguage.t(this, "Unlock MyKit to fill", "افتح MyKit للملء")
        } else {
            AppLanguage.t(
                this,
                "MyKit: turn on fingerprint unlock to fill",
                "MyKit: فعّل الفتح بالبصمة للملء",
            )
        }
        val presentation = RemoteViews(packageName, R.layout.autofill_item).apply {
            setTextViewText(R.id.autofill_text, label)
        }
        val intent = Intent(this, AutofillAuthActivity::class.java)
            .putExtra(AutofillAuthActivity.EXTRA_USERNAME_ID, fields.username)
            .putExtra(AutofillAuthActivity.EXTRA_PASSWORD_ID, fields.password)
            .putExtra(AutofillAuthActivity.EXTRA_PACKAGE, fields.packageName)
            .putExtra(AutofillAuthActivity.EXTRA_DOMAIN, fields.webDomain)
        val sender = PendingIntent.getActivity(
            this,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_MUTABLE,
        ).intentSender

        // One locked dataset; once unlocked, the chosen login replaces it and
        // is filled straight away.
        val dataset = Dataset.Builder().apply {
            fields.ids.forEach { setValue(it, null as AutofillValue?, presentation) }
            setAuthentication(sender)
        }.build()
        callback.onSuccess(FillResponse.Builder().addDataset(dataset).build())
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // Saving new logins comes later; nothing is requested yet.
        callback.onSuccess()
    }

    companion object {
        private const val REQUEST_CODE = 4207
    }
}
