package site.wingspot.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp

/** Where the legal pages and the contact address live. The pages are published on wingspot.site. */
object LegalLinks {
    /**
     * Set to `true` once the pages and the mailbox below are online. Until then the links stay out of the app, so nobody
     * opens an empty page. The iPhone app has the same switch in `LegalLinks.pagesAreLive`.
     */
    const val PAGES_ARE_LIVE = false
    const val PRIVACY = "https://wingspot.site/privacy"
    const val TERMS = "https://wingspot.site/terms"
    const val IMPRINT = "https://wingspot.site/imprint"
    const val CONTACT_ADDRESS = "support@wingspot.site"
}

/**
 * Privacy policy, terms, imprint and contact, for Settings and the sign-in screen. [compact] is the sign-in screen: the
 * privacy policy and terms with the line that signing in accepts them.
 */
@Composable
fun LegalLinksSection(compact: Boolean = false, live: Boolean = LegalLinks.PAGES_ARE_LIVE) {
    if (!live) return
    val uri = LocalUriHandler.current
    Column(Modifier.fillMaxWidth().testTag("legal-links"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (!compact) Text(stringResource(R.string.legal_about), style = MaterialTheme.typography.titleMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { uri.openUri(LegalLinks.PRIVACY) }, modifier = Modifier.testTag("legal-privacy")) { Text(stringResource(R.string.legal_privacy)) }
            TextButton(onClick = { uri.openUri(LegalLinks.TERMS) }, modifier = Modifier.testTag("legal-terms")) { Text(stringResource(R.string.legal_terms)) }
        }
        if (!compact) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { uri.openUri(LegalLinks.IMPRINT) }, modifier = Modifier.testTag("legal-imprint")) { Text(stringResource(R.string.legal_imprint)) }
                TextButton(onClick = { uri.openUri("mailto:" + LegalLinks.CONTACT_ADDRESS) }, modifier = Modifier.testTag("legal-contact")) {
                    Text(stringResource(R.string.legal_contact) + ": " + LegalLinks.CONTACT_ADDRESS)
                }
            }
        } else {
            Text(stringResource(R.string.legal_sign_in_accept), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
