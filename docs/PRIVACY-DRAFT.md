# Privacy policy: draft for wingspot.site

This is a working draft, not legal advice. It describes what the app does today (version 0.2.0). Anything in `[brackets]` needs your input. Have it read by someone qualified before it goes live, and update it when features change (feed, comments, analytics, crash reporting).

---

## Deutsch

# Datenschutzerklärung

**Verantwortlicher:** [Name, Anschrift, E-Mail]

## Was Wingspot speichert

- **Konto:** deine E-Mail-Adresse oder die Kennung von „Anmelden mit Apple" (iPhone; bei Apple ggf. eine Relay-Adresse) oder von „Anmelden mit Google" (Android), dein Anzeigename und dein Heimatflughafen.
- **Check-ins:** Art (Gespottet, Flughafen, Geflogen), Zeitpunkt, Flughafen, Kennzeichen und Flugzeugtyp, bei Flügen Strecke, Flugnummer, Kabine und Sitz. Dazu der Standort, den du beim Check-in mitgibst.
- **Fotos:** Fotos, die du einem Check-in hinzufügst.
- **Soziales:** dein Benutzername, wem du folgst und wer dir folgt, wen du blockiert hast, deine Freigabe-Einstellungen (zu Beginn „Nur ich“), Kommentare und Salutes, die du schreibst oder gibst, und Meldungen, die du abschickst. Check-ins sind nur für die sichtbar, die du zugelassen hast: nur du, Freunde (ihr folgt euch gegenseitig) oder alle. Eine Verzögerung kann öffentliche Check-ins für Fremde zurückhalten. Dein genauer Standort wird anderen nie gezeigt.
- **Mitteilungen:** wenn du Mitteilungen erlaubst, speichern wir eine Gerätekennung für Mitteilungen (Push-Token), die Sprache deines Geräts und die App-Version, damit wir dir Mitteilungen schicken können, wenn dir jemand folgt oder einen deiner Check-ins salutiert oder kommentiert. Sie werden über den Apple-Dienst für Mitteilungen (iPhone) bzw. Firebase Cloud Messaging von Google (Android) zugestellt und enthalten einen Namen und den Anfang eines Kommentars; ob das auf dem Sperrbildschirm erscheint, stellst du in den Geräteeinstellungen ein. Du kannst für Personen, denen du folgst, Hinweise auf neue Check-ins einschalten; die andere Person erfährt davon nichts und sieht diese Liste nicht. Du kannst jede Art in der App ausschalten. Beim Abmelden wird das Gerät entfernt.
- **Auf deinem Gerät:** Check-ins werden zuerst offline auf dem Gerät gespeichert und später hochgeladen. Ohne Konto bleiben sie auf dem Gerät.

## Standort

Wingspot fragt den Standort nur, wenn du ihn benutzt, etwa um den nächsten Flughafen vorzuschlagen. Der Standort eines Check-ins wird gespeichert, aber **nicht anderen angezeigt**.

## Fotos

Vor dem Hochladen verkleinert die App das Foto und speichert eine neue Datei **ohne Metadaten** (kein Standort, keine Kamera- oder Zeitangaben). Das Original wird nicht gespeichert. Der Server lehnt Fotos mit Metadaten ab. Fotos liegen in einem privaten Speicher. Sie sind nur für dich sichtbar, solange du Check-ins nicht teilst; teilst du einen Check-in, sehen sein Foto die Personen, die den Check-in sehen dürfen (Freunde oder alle, je nach Einstellung). Fotos von sensiblen Luftfahrzeugen (z. B. Militär, Regierung) werden nie anderen gezeigt.

## Bordkarten-Scan

Die Bordkarte wird **nur auf deinem Gerät** gelesen. Aus dem Code werden nur Strecke, Datum, Flugnummer und Sitz übernommen. **Name und Buchungscode werden weder gelesen noch gespeichert oder übertragen.** Die Kamera wird nur dafür benutzt; Bilder werden nicht gespeichert oder hochgeladen.

## Wo die Daten liegen

Bei Supabase, in Frankfurt (EU). [Auftragsverarbeitungsvertrag mit Supabase abschließen und hier bestätigen.] Der Versand von Anmelde-E-Mails läuft über [Dienst eintragen]. Apps werden über Apple (App Store, TestFlight) bzw. Google (Play Store) verteilt; diese verarbeiten dabei eigene Daten nach ihren Datenschutzerklärungen. Die Android-App lädt Kartenkacheln von Google Maps; dabei erhält Google deine IP-Adresse und den angezeigten Kartenausschnitt. Das Lesen einer Bordkarte (Kamera oder Bild) passiert nur auf deinem Gerät; Name und Buchungscode werden weder gelesen noch gespeichert.

## Analyse und Abstürze

Derzeit verwendet Wingspot **keine** eigenen Analyse- oder Absturzdienste. Wenn du in den iPhone-Einstellungen das Teilen von Analysedaten erlaubt hast, erhalten wir über Apple (TestFlight, App Store) Absturzberichte, ohne dich zu identifizieren. [Ändern, falls TelemetryDeck oder Sentry eingebaut werden.]

## Rechtsgrundlagen

Vertragserfüllung (Art. 6 Abs. 1 lit. b DSGVO) für Konto und Check-ins, Einwilligung (lit. a) für Standort und Kamera/Fotos.

## Deine Rechte

Auskunft, Berichtigung, Löschung, Einschränkung, Datenübertragbarkeit und Widerspruch, sowie Beschwerde bei einer Aufsichtsbehörde. Schreibe an [E-Mail]. Du kannst dein Konto direkt in der App unter Profil löschen. Deine Daten kannst du dort auch als Datei exportieren.

## Speicherdauer

Bis du dein Konto löschst. Dann werden Konto, Check-ins, Fotos, Kommentare, Follows und Geräte sofort und endgültig gelöscht. Meldungen, die du abgegeben hast, bleiben ohne Bezug zu dir erhalten.

## Kinder

Wingspot richtet sich nicht an Kinder unter [16] Jahren.

Stand: [Datum]

---

## English

# Privacy policy

**Controller:** [name, address, email]

## What Wingspot stores

- **Account:** your email address your "Sign in with Apple" identifier (iPhone; possibly an Apple relay address) or your "Sign in with Google" identifier (Android), your display name and your home airport.
- **Check-ins:** type (Spotted, Airport, Flown), time, airport, registration and aircraft type, and for flights the route, flight number, cabin and seat. Plus the location you share when checking in.
- **Photos:** photos you add to a check-in.
- **Social:** your username, who you follow and who follows you, who you blocked, your sharing settings ("Only me" at first), comments and salutes you write or give, and reports you send. A check-in is visible only to those you allow: only you, friends (you follow each other) or everyone. A delay can hold public check-ins back from strangers. Your exact location is never shown to others.
- **Notifications:** if you allow notifications, we store a device identifier for notifications (push token), your device's language and the app version, so we can notify you when someone follows you or salutes or comments on one of your check-ins. They are delivered through Apple's notification service (iPhone) or Google's Firebase Cloud Messaging (Android) and contain a name and the start of a comment; whether that shows on the lock screen is set in the device settings. For people you follow you can switch on alerts for their new check-ins; the other person is not told and cannot see this list. You can switch off each kind in the app. Signing out removes the device.
- **On your device:** check-ins are saved offline first and uploaded later. Without an account they stay on the device.

## Location

Wingspot asks for your location only when you use it, for example to suggest the nearest airport. A check-in's location is stored but **not shown to others**.

## Photos

Before upload, the app shrinks the photo and writes a new file **without metadata** (no location, camera or date information). The original is not kept. The server rejects photos that carry metadata. Photos are kept in private storage. They are visible only to you while you do not share check-ins; if you share a check-in, the people who may see that check-in can see its photo (friends or everyone, depending on your setting). Photos of sensitive aircraft (for example military or government) are never shown to others.

## Boarding pass scan

The boarding pass is read **only on your device**. Only route, date, flight number and seat are taken from the code. **The passenger name and booking code are neither read, stored nor sent.** The camera is used only for this; images are not saved or uploaded.

## Where data is kept

With Supabase, in Frankfurt (EU). [Sign a data processing agreement with Supabase and confirm here.] Sign-in emails are sent through [service]. The apps are distributed through Apple (App Store, TestFlight) and Google (Play Store); they process their own data under their privacy policies. The Android app loads map tiles from Google Maps, so Google receives your IP address and the map area shown. Reading a boarding pass (camera or picture) happens on your device only; the name and booking code are neither read nor stored.

## Analytics and crashes

Wingspot currently uses **no** analytics or crash reporting of its own. If you allowed sharing analytics in the iPhone settings, we receive crash reports through Apple (TestFlight, App Store) without identifying you. [Change if TelemetryDeck or Sentry is added.]

## Legal bases

Contract (Art. 6(1)(b) GDPR) for account and check-ins; consent (point (a)) for location and camera/photos.

## Your rights

Access, correction, deletion, restriction, portability and objection, and a complaint to a supervisory authority. Write to [email]. You can delete your account in the app under Profile. You can also export your data as a file there.

## Retention

Until you delete your account; then your account, check-ins, photos, comments, follows and devices are deleted immediately and for good. Reports you filed remain, without a link to you.

## Children

Wingspot is not aimed at children under [16].

Last updated: [date]
