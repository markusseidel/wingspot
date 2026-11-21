# Plan: the Wingspot website on wingspot.site

Status: plan only, nothing is built. The domain `wingspot.site` is bought and managed at STRATO (strato.de). This plan
collects every place in the apps, the stores and the backend that needs a website or the domain, and turns each into a
todo. Todos marked **Owner** need your accounts or decisions; the others are work for the repository.

## 1. Where a website or the domain is needed

| # | Need | Where it comes from | Blocks |
| --- | --- | --- | --- |
| 1 | **Privacy policy** page (German and English) | `docs/PRIVACY-DRAFT.md`, Apple App Privacy and App Review, Google Play Data safety, Google OAuth consent screen | App Store release, Play production, Google sign-in verification |
| 2 | **Terms of use** page | `docs/TERMS-DRAFT.md`, community rules in the feed gate | Social features in review |
| 3 | **Imprint (Impressum)** page | German law for a commercial or regular offer; `LegalLinks.imprint` | Publishing the app in Germany |
| 4 | **Support address and page** `support@wingspot.site` | `LegalLinks.contactAddress`, App Store "Support URL" (required), Play listing contact | App Store release |
| 5 | **Account deletion page** (a web address that explains how to delete the account and data) | Google Play requires a web URL for account deletion | Play production |
| 6 | **`LegalLinks.pagesAreLive = true`** in the iPhone app and the same switch on Android | `ios/Wingspot/Features/Settings/LegalLinks.swift`: the links are hidden until the pages exist | The legal links showing up in the apps |
| 7 | **Universal Links (iOS) and App Links (Android)** | `docs/CONCEPT.md` section 9, `docs/ANDROID.md` (`assetlinks.json`), `docs/TODO.md` (universal links) | Shared links opening the app |
| 8 | **Invite links** `https://wingspot.site/invite/CODE` instead of `wingspot://invite/CODE` | `docs/SOCIAL-PLAN.md` decision 1 and step 1b; links in WhatsApp and Mail are not tappable as a custom scheme | Invites reaching people without the app |
| 9 | **Landing page for a shared link** (a person without the app sees what was shared and a store button) | `docs/CONCEPT.md` section 9, `docs/TODO.md` ("shared-link pages in both languages") | Share cards and invites doing their job |
| 10 | **Link previews** (title, picture, description when a link is pasted in a chat) | Share cards, invites, check-in links | Nice sharing |
| 11 | **Public profile and check-in pages** (opt-in, public data only) | `docs/SOCIAL-PLAN.md` ("public profile page"), `docs/CONCEPT.md` section 16 | Later, optional |
| 12 | **Spotting place pages** `/s/{id}` (approved places only) | Spotting locations (issue 218) | Later, optional |
| 13 | **Sign-in emails from the domain** (sender, SPF, DKIM, DMARC) | Sign-in by email link, Supabase Auth; the default mail sender is rate limited and looks anonymous | Reliable sign-in mails at scale |
| 14 | **Sign-in link target**: allowed redirect URLs and the site URL in Supabase Auth | `backend/supabase/config.toml` (`site_url`, `additional_redirect_urls`) and the hosted project settings | Sign-in link working on a web fallback |
| 15 | **Google sign-in (Android)**: OAuth consent screen with home page, privacy and terms links, and an authorized domain | `docs/ANDROID-BETA.md` | Leaving "testing" mode, more than 100 users |
| 16 | **App Store and Google Play listing fields**: marketing URL, support URL, privacy URL | Both stores | Submission |
| 17 | **Store webhooks** (App Store Server Notifications, Play notifications, and an App Store Connect to Slack relay) | `docs/CONCEPT.md` section 12, discussed for Slack | Only when purchases or the relay are built; a function URL from Supabase is enough, the domain is optional (section 8) |
| 18 | **Demo account address** `review@wingspot.site` | `docs/MILESTONE10.md` (seed script) | Needs no mailbox, only to stay consistent |

Items 1 to 6 and 16 are needed before the first public App Store release. Items 7 to 10 and 13 are needed for sharing
to feel finished. Items 11 and 12 are later.

## 2. Decisions to take first

1. **Where is the site hosted?** Options:
   - **A. STRATO webspace** (if the contract includes hosting, files by SFTP, TLS certificate from STRATO). Simplest if
     it is already paid for; deployments are manual unless a script is added.
   - **B. A static host with the DNS kept at STRATO** (GitHub Pages, Cloudflare Pages or Netlify): the site is built from
     this repository on every merge, free for this size, automatic certificates. STRATO only holds the DNS records
     (an `A` or `AAAA` record for the main name and a `CNAME` for `www`).
   - **C. Move the nameservers away from STRATO** to the static host (or Cloudflare). Gives full DNS control and
     redirect rules, but STRATO's own mail setup then needs its DNS records copied (STRATO notes that with your own
     nameservers you maintain the DKIM entries yourself).
   - **Recommended: B**, with the site files in this repository under `web/` and deployed by a GitHub Action. Reason:
     reviewable pages in pull requests, no manual uploads, and the two special files in section 5 are served
     with the right headers.
2. **Mailbox**: `support@wingspot.site` as a real STRATO mailbox (if the package has mail) or as a forward to your own
   address. Sending the app's sign-in mails is a separate service (section 7).
3. **Site generator**: plain HTML and CSS (recommended: nothing to maintain, six to ten pages), or a small static
   generator if the number of pages and translations grows.
4. **Languages**: German and English from the start; English default at `/`, German at `/de/`, with a language switch and
   `hreflang` tags.
5. **Imprint details**: which address goes in the Impressum (a private address is public then; some people use a c/o or
   Impressum service). **Owner.**
6. **Dynamic pages** (items 10 to 12): build now, or ship the static site first (recommended: static first, dynamic in
   phase 4).

## 3. The pages (static site, phases 1 and 2)

All in German and English. No cookies, no analytics, no external fonts or scripts, so no cookie banner is needed.

| Page | Address | Content and source |
| --- | --- | --- |
| Home | `/` | What Wingspot is, three screenshots, App Store and Google Play buttons (until live: TestFlight and beta text), contact |
| Privacy policy | `/privacy` | From `docs/PRIVACY-DRAFT.md` with the brackets filled in; must name the hosting provider of the site and of the backend (Supabase), what is stored, rights, contact; link to the data export and deletion in the app |
| Terms of use | `/terms` | From `docs/TERMS-DRAFT.md`; reports are read in the `reports` table within 24 hours (as the rules promise) |
| Imprint | `/imprint` | Name, address, contact, as the law requires (section 10) |
| Support | `/support` | `support@wingspot.site`, how to report a person or check-in, how to export data, FAQ |
| Delete account | `/delete-account` | How: Profile, Delete account in the app, two confirmations; what is removed; what to do without the app (email from the account's address); time to delete |
| Invite and share fallback | `/invite/{code}`, `/u/...`, `/c/...`, `/a/...`, `/r/...`, `/b/...`, `/s/...` | Phase 2: one generic page ("Open in Wingspot" or "Get Wingspot") that works for every link pattern; phase 4 adds real previews |
| 404 | `/404.html` | Short, with a link home |
| Files | `/robots.txt`, `/sitemap.xml`, `/favicon.ico`, `/apple-touch-icon.png`, `/og/default.png` | |

Todos:
- [ ] **Owner:** fill in the brackets in the privacy draft and the terms draft (name, address, contact, hosting
      providers), have them read once (a lawyer or a service like eRecht24 or IT-Recht Kanzlei is worth it for the
      Impressum and the privacy text).
- [ ] Build the pages in `web/` (plain HTML and CSS, one shared stylesheet, light and dark, mobile first, accessible).
- [ ] German and English versions of every page, with `hreflang` and a visible language switch.
- [ ] Real screenshots and the app icon for the home page (the same ones as the store listing).
- [ ] A pull-request preview or a local `python3 -m http.server` check for every page; link checker in CI.

## 4. DNS and hosting setup (STRATO)

Where: STRATO customer login, Domains, Domainverwaltung, gear icon next to the domain, DNS tab (per STRATO's help pages).
Changes can take up to 24 hours. Things STRATO's help states and we must check on this contract:
- Own `A`, `AAAA` and `TXT` records for the domain and `CNAME` for subdomains are possible; some settings are inactive
  when STRATO's own mail or web package is attached. **Owner: check which package `wingspot.site` has (domain only,
  with mail, with webspace).**
- The NS record cannot be changed while an own MX, A or SPF record is set; DNSSEC works only with STRATO's nameservers
  (Domain Guard). Decide whether DNSSEC matters (not needed for the apps).

DNS records to plan (values come from the host and the mail provider, never written into this repository):

| Name | Type | Purpose |
| --- | --- | --- |
| `wingspot.site` | `A` and `AAAA` (or the host's alias record) | The website |
| `www` | `CNAME` | Redirect to the main name |
| `wingspot.site` | `MX` | Incoming mail for `support@` (STRATO's, unless the mailbox is a forward) |
| `wingspot.site` | `TXT` (SPF) | One SPF record listing every sender: STRATO mail and the sign-in mail service |
| `selector._domainkey` | `TXT` or `CNAME` | DKIM for the sign-in mail service (and STRATO's, if used) |
| `_dmarc` | `TXT` | DMARC policy, start with `p=none` and a report address, later `quarantine` |
| `_acme-challenge` or the host's verification name | `TXT` / `CNAME` | Certificate or ownership checks, if the host asks |
| `api` (optional) | `CNAME` | A custom domain for the backend (section 8) |

Todos:
- [ ] **Owner:** check the STRATO package and whether you can edit DNS records and mail; write down the answers here.
- [ ] **Owner:** decide A, B or C from section 2 and create the account at the static host (if B or C).
- [ ] Create the DNS records above one block at a time (website first, mail later), checking each with `dig`.
- [ ] HTTPS only, `www` and `http` redirect to `https://wingspot.site`, HSTS once everything works.
- [ ] Turn on registrar lock and auto renew for the domain; add a calendar reminder for the renewal date.

## 5. Universal Links and App Links (items 7 and 8)

Two files must be served from the domain root, over HTTPS, without redirects:

`https://wingspot.site/.well-known/apple-app-site-association` (JSON, no file extension, `Content-Type:
application/json`):
```json
{ "applinks": { "details": [ { "appIDs": ["Z6K89AW5QT.site.wingspot.ios"],
  "components": [ { "/": "/invite/*" }, { "/": "/u/*" }, { "/": "/c/*" }, { "/": "/a/*" },
                  { "/": "/r/*" }, { "/": "/b/*" }, { "/": "/s/*" } ] } ] } }
```
`https://wingspot.site/.well-known/assetlinks.json`:
```json
[ { "relation": ["delegate_permission/common.handle_all_urls"],
    "target": { "namespace": "android_app", "package_name": "site.wingspot.android",
                "sha256_cert_fingerprints": ["<fingerprint of the Play App Signing key>", "<upload or debug key, for testing>"] } } ]
```
The team ID and the package names above are the ones in `ios/project.yml` and `android/app/build.gradle.kts`. GitHub Pages
hides dot folders unless a `.nojekyll` file exists; the file must not be redirected or served with a login or a cache
that serves an old version.

Link patterns (same on both platforms): `/invite/{code}`, `/u/{username}`, `/c/{checkinId}`, `/a/{icao}`,
`/r/{registration}`, `/b/{badgeId}`, `/s/{spotId}`, plus the existing `wingspot://invite/CODE` and `wingspot://auth-callback`
which keep working.

Todos:
- [ ] Add the two files to `web/.well-known/` with the headers above (host config) and a CI check that they parse.
- [ ] **Owner:** copy the SHA-256 fingerprint of the app signing key from Google Play Console (Setup, App signing) and
      of the upload key; the debug key only for local tests. Never commit a keystore.
- [ ] iPhone: add the Associated Domains entitlement `applinks:wingspot.site` (`ios/Wingspot/Wingspot.entitlements` and
      `project.yml`), handle `onOpenURL` and `NSUserActivity` for the https links, same routing as the `wingspot://` links.
- [ ] Android: add `intent-filter`s with `android:autoVerify="true"`, scheme `https`, host `wingspot.site` and the path
      prefixes, route them like the existing invite link in `AppScreen`/`SocialViewModel`.
- [ ] Change the invite and share text in both apps from `wingspot://invite/CODE` to `https://wingspot.site/invite/CODE`
      (the QR code too); the old link keeps working for people with an older build.
- [ ] Test: tap the link in Messages, Mail, WhatsApp and Notes on a real iPhone and an Android phone with and without
      the app installed; `adb shell pm get-app-links site.wingspot.android` and the Apple validator of the AASA file.
- [ ] Note: iOS caches the AASA through Apple's CDN, so a change can take hours; test with a fresh install.

## 6. The page behind a shared link (items 9 and 10)

Phase 2 (static): one page for every pattern above. It shows "Open in Wingspot" (works when the app does not take the
link) and store buttons, in the visitor's language, with a smart app banner meta tag for Safari. It shows nothing about
a person or check-in, so it needs no data and leaks nothing.

Phase 4 (dynamic previews): when a link is pasted into WhatsApp, Mail or Slack, the chat app fetches the page and reads
its title, description and picture. To show the real content the page needs data from the backend:
- A small Supabase Edge Function (or a Cloudflare Worker) answers `GET /u/{username}`, `/c/{id}`, `/b/{id}`, `/s/{id}`
  with HTML that has Open Graph and Twitter card tags and a picture, reading **only public data** through a read-only
  function that follows the same rules as the app (`can_view_profile_content`, blocks, private profiles, check-in
  visibility, the delay setting). Private profiles and check-ins that are not public return the generic page.
- Pictures: the share card generator exists in the apps; for the web, render a card image on the server or reuse a stored
  image. Hidden badges are never shown, before or after they are earned in a public preview.
- Caching: a short cache (minutes) so that a changed visibility takes effect quickly; `noindex` on person pages unless
  the person opted into a public page.
- New function names go into `access_test.sql`, with tests for each access case, like every function that returns other
  people's data.

Todos:
- [ ] Decide whether public web profiles are wanted at all and add an opt-in switch in Settings (default off) before any
      person page is served.
- [ ] Build the read-only functions and tests, then the edge function or worker, then the previews.
- [ ] Add the pages to the privacy policy (what a public page shows, how to turn it off).

## 7. Email from the domain (items 13 and 14)

Today the sign-in email link is sent by Supabase Auth. **Owner: check Supabase dashboard, Authentication, SMTP.** The
default sender is for testing: it is rate limited, only for team addresses on some plans, and goes to spam more often.

Todos:
- [ ] Choose a transactional mail service (for example Resend, Postmark, Brevo or the STRATO SMTP server) and create an
      account; an EU region is preferable for the privacy text.
- [ ] Add the domain at the service, then the SPF, DKIM and DMARC records from section 4 and wait for "verified".
- [ ] In Supabase, set the custom SMTP (host, port, user, password as a secret, sender `Wingspot <login@wingspot.site>`),
      and customise the sign-in email text in German and English (the template files are in
      `backend/supabase/config.toml` under `auth.email.template`).
- [ ] Set the Supabase **Site URL** to `https://wingspot.site` and keep `wingspot://auth-callback` in the allowed
      redirect URLs, so the sign-in link opens the app (and a web fallback page can explain what to do).
- [ ] Send test mails to Gmail, Outlook, iCloud and GMX/web.de, check spam folders and the DMARC reports.
- [ ] The support mailbox: reply-to for the sign-in mails is `support@wingspot.site`.
- [ ] Rate limits: decide a per-hour limit that fits the beta and raise it before launch.

## 8. Backend addresses (item 17)

The App Store Server Notifications, Google Play real-time notifications and an App Store Connect to Slack relay are
plain HTTPS endpoints. They can be Supabase Edge Function URLs (`https://<project>.functions.supabase.co/...`) with no
domain work. A nicer, stable address such as `https://api.wingspot.site` needs Supabase's custom domain feature (a paid
add-on) and a `CNAME` record. Not needed for the website; decide when purchases are built.
- [ ] Decide later: keep the Supabase URLs, or buy the custom domain add-on for `api.wingspot.site`.
- [ ] The Slack relay (App Store Connect webhooks): verify Apple's signature, post to a Slack incoming webhook stored
      as a Supabase secret; only if you want it (you said not for now).

## 9. Store and Google fields (items 15 and 16)

- [ ] **App Store Connect**: Privacy Policy URL `https://wingspot.site/privacy`, Support URL `https://wingspot.site/support`,
      Marketing URL `https://wingspot.site`; the App Privacy answers must match the privacy page.
- [ ] **Google Play Console**: privacy policy URL, the account deletion URL `https://wingspot.site/delete-account`, the
      Data safety form (same facts as the privacy page), store listing contact email and website.
- [ ] **Google Cloud OAuth consent screen**: application home page `https://wingspot.site`, privacy and terms links, the
      authorized domain `wingspot.site`; Google asks to verify ownership of the domain in **Search Console** (a `TXT`
      record). Then move the consent screen from testing to production.
- [ ] Apple Sign in with the web flow on Android: a Services ID with the domain and return URL if that flow is kept
      (`docs/ANDROID.md` item 3).
- [ ] Update `docs/TESTFLIGHT.md`, `docs/ANDROID-BETA.md` and `docs/TODO.md` with the live addresses.

## 10. Legal checklist (Germany and the EU)

- [ ] **Impressum** (DDG section 5): name, a postal address that can receive mail, a way to contact quickly (email, and a
      second contact such as a form or phone), and, if it applies, register and VAT numbers. Reachable from every page
      in at most two clicks (a footer link).
- [ ] **Privacy policy** (GDPR): controller, purposes and legal bases, recipients (Supabase, Apple and Google push, the
      mail service, the site host), the countries where data goes and the safeguards, storage periods, rights and how to
      use them, the right to complain to the authority. State what the website itself logs (the host's server logs, IP
      addresses) and for how long.
- [ ] **Data processing agreements** with the site host, the mail service and Supabase (most offer one online).
- [ ] **Terms of use** (section 2) and the community rules link from the apps.
- [ ] **Digital Services Act**: the app stores ask for trader status and contact details; the Impressum address is
      shown to users in the EU listing.
- [ ] **Accessibility**: the pages meet the basics (contrast, headings, alt text, keyboard use); the European
      Accessibility Act applies to some consumer services, check whether it applies to this app and site.
- [ ] No cookies and no tracking on the site. If analytics are wanted later, use a cookieless one and update the privacy
      page; a banner is then not needed.

## 11. App changes that go with the website (both platforms, same change)

- [ ] Flip the legal links on: `LegalLinks.pagesAreLive = true` (iPhone) and the same switch on Android, in the same PR
      as the live pages, so no build shows links to empty pages.
- [ ] Settings, About: privacy, terms, imprint, contact (already built, hidden until live), plus a link to the website.
- [ ] Invite and share links use the https address (section 5).
- [ ] The sign-in screen footer links the terms and privacy (built, shown when the pages are live).
- [ ] Release the iPhone and Android build together with a tester text.

## 12. Phases, order and rough effort

| Phase | What | Needs | Effort |
| --- | --- | --- | --- |
| 0 | Decisions in section 2, STRATO package check, host account, mailbox | Owner | 1 to 2 hours |
| 1 | Static site with legal pages, support, delete account, home; DNS for the website; HTTPS | Owner texts, then 1 day | 1 day plus the legal review |
| 2 | Universal and App Links, invite links on https, generic link page, app changes, tests on real phones | Phase 1, signing fingerprints | 1 to 2 days |
| 3 | Sign-in mail from the domain (SMTP, SPF, DKIM, DMARC), Supabase site URL, Google consent screen and Search Console | Phase 1 | 0.5 to 1 day |
| 4 | Store fields (App Store Connect, Play Console) and the flip of `pagesAreLive`; one build | Phases 1 to 3 | 0.5 day |
| 5 | Optional: public profile opt-in, read-only functions, link previews, place pages | Decisions in section 6 | 3 to 5 days |
| 6 | Optional: custom backend domain, Slack relay | Purchases or your wish | 0.5 day each |

Order for the first public release: 0, 1, 3, 4 (legal pages, mail, store fields), then 2 (links), then 5 and 6.

## 13. Costs and upkeep

- Domain renewal at STRATO (check the yearly price on the invoice; `.site` domains often cost more at renewal than in the
  first year). Static hosting for this size is free at GitHub Pages and Cloudflare Pages.
- A transactional mail service has a free tier that covers a beta; plan a small monthly fee beyond it.
- Upkeep: renew the domain, keep the legal pages current when features change (for example public profiles or purchases),
  check the DMARC reports now and then, renew the Apple web-flow key every six months if it is used.

## 14. Risks

- Sign-in mails landing in spam or being rate limited is the most likely beta problem; phase 3 removes it.
- A wrong or missing `assetlinks.json` or AASA file silently disables the links; the checks in section 5 catch it.
- Legal text that does not match what the app does is worse than no text; update it with every feature that stores new
  data.
- DNS changes at STRATO can take up to 24 hours, and moving nameservers can break STRATO mail; change one record group
  at a time.
- A public web profile exposes data outside the app; it stays off until the opt-in exists and is tested.

## 15. Open questions for the owner

1. What does the STRATO contract for `wingspot.site` include (webspace, mailboxes, DNS editing)?
2. Hosting option A, B or C (recommended B)?
3. Which postal address goes in the Impressum?
4. Which mail service for the sign-in mails (or the STRATO SMTP server)?
5. Public web profiles and check-in pages: wanted, and when?
6. Should the website be released before the next App Store submission (the legal pages are needed for it)?
