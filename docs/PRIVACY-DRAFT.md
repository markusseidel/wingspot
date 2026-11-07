# Privacy policy: draft for wingspot.site

This is a working draft, not legal advice. It describes what the app does today (version 0.2.0). Anything in `[brackets]` needs your input. Have it read by someone qualified before it goes live, and update it when features change (feed, comments, analytics, crash reporting).

---

## Deutsch

# Datenschutzerklärung

**Verantwortlicher:** [Name, Anschrift, E-Mail]

## Was Wingspot speichert

- **Konto:** deine E-Mail-Adresse oder die Kennung von „Anmelden mit Apple" (bei Apple ggf. eine Relay-Adresse), dein Anzeigename und dein Heimatflughafen.
- **Check-ins:** Art (Gespottet, Flughafen, Geflogen), Zeitpunkt, Flughafen, Kennzeichen und Flugzeugtyp, bei Flügen Strecke, Flugnummer, Kabine und Sitz. Dazu der Standort, den du beim Check-in mitgibst.
- **Fotos:** Fotos, die du einem Check-in hinzufügst.
- **Auf deinem Gerät:** Check-ins werden zuerst offline auf dem Gerät gespeichert und später hochgeladen. Ohne Konto bleiben sie auf dem Gerät.

## Standort

Wingspot fragt den Standort nur, wenn du ihn benutzt, etwa um den nächsten Flughafen vorzuschlagen. Der Standort eines Check-ins wird gespeichert, aber **nicht anderen angezeigt**.

## Fotos

Vor dem Hochladen verkleinert die App das Foto und speichert eine neue Datei **ohne Metadaten** (kein Standort, keine Kamera- oder Zeitangaben). Das Original wird nicht gespeichert. Der Server lehnt Fotos mit Metadaten ab. Fotos liegen in einem privaten Speicher. Sie sind nur für dich sichtbar, solange du Check-ins nicht teilst; teilst du einen Check-in, sehen sein Foto die Personen, die den Check-in sehen dürfen (Freunde oder alle, je nach Einstellung). Fotos von sensiblen Luftfahrzeugen (z. B. Militär, Regierung) werden nie anderen gezeigt.

## Bordkarten-Scan

Die Bordkarte wird **nur auf deinem Gerät** gelesen. Aus dem Code werden nur Strecke, Datum, Flugnummer und Sitz übernommen. **Name und Buchungscode werden weder gelesen noch gespeichert oder übertragen.** Die Kamera wird nur dafür benutzt; Bilder werden nicht gespeichert oder hochgeladen.

## Wo die Daten liegen

Bei Supabase, in Frankfurt (EU). [Auftragsverarbeitungsvertrag mit Supabase abschließen und hier bestätigen.] Der Versand von Anmelde-E-Mails läuft über [Dienst eintragen]. Apps werden über Apple (App Store, TestFlight) verteilt; Apple verarbeitet dabei eigene Daten nach seiner Datenschutzerklärung.

## Analyse und Abstürze

Derzeit verwendet Wingspot **keine** Analyse- oder Absturzdienste. [Ändern, falls TelemetryDeck oder Sentry eingebaut werden.]

## Rechtsgrundlagen

Vertragserfüllung (Art. 6 Abs. 1 lit. b DSGVO) für Konto und Check-ins, Einwilligung (lit. a) für Standort und Kamera/Fotos.

## Deine Rechte

Auskunft, Berichtigung, Löschung, Einschränkung, Datenübertragbarkeit und Widerspruch, sowie Beschwerde bei einer Aufsichtsbehörde. Schreibe an [E-Mail]. [Sobald die App es kann: Konto löschen und Daten exportieren direkt in den Einstellungen.]

## Speicherdauer

Bis du dein Konto löschst. Dann werden Konto, Check-ins und Fotos gelöscht. [Mit Meilenstein 8 prüfen.]

## Kinder

Wingspot richtet sich nicht an Kinder unter [16] Jahren.

Stand: [Datum]

---

## English

# Privacy policy

**Controller:** [name, address, email]

## What Wingspot stores

- **Account:** your email address or your "Sign in with Apple" identifier (possibly an Apple relay address), your display name and your home airport.
- **Check-ins:** type (Spotted, Airport, Flown), time, airport, registration and aircraft type, and for flights the route, flight number, cabin and seat. Plus the location you share when checking in.
- **Photos:** photos you add to a check-in.
- **On your device:** check-ins are saved offline first and uploaded later. Without an account they stay on the device.

## Location

Wingspot asks for your location only when you use it, for example to suggest the nearest airport. A check-in's location is stored but **not shown to others**.

## Photos

Before upload, the app shrinks the photo and writes a new file **without metadata** (no location, camera or date information). The original is not kept. The server rejects photos that carry metadata. Photos are kept in private storage. They are visible only to you while you do not share check-ins; if you share a check-in, the people who may see that check-in can see its photo (friends or everyone, depending on your setting). Photos of sensitive aircraft (for example military or government) are never shown to others.

## Boarding pass scan

The boarding pass is read **only on your device**. Only route, date, flight number and seat are taken from the code. **The passenger name and booking code are neither read, stored nor sent.** The camera is used only for this; images are not saved or uploaded.

## Where data is kept

With Supabase, in Frankfurt (EU). [Sign a data processing agreement with Supabase and confirm here.] Sign-in emails are sent through [service]. The app is distributed through Apple (App Store, TestFlight); Apple processes its own data under its privacy policy.

## Analytics and crashes

Wingspot currently uses **no** analytics or crash reporting. [Change if TelemetryDeck or Sentry is added.]

## Legal bases

Contract (Art. 6(1)(b) GDPR) for account and check-ins; consent (point (a)) for location and camera/photos.

## Your rights

Access, correction, deletion, restriction, portability and objection, and a complaint to a supervisory authority. Write to [email]. [Once the app supports it: delete your account and export your data in Settings.]

## Retention

Until you delete your account; then your account, check-ins and photos are deleted. [Verify with Milestone 8.]

## Children

Wingspot is not aimed at children under [16].

Last updated: [date]
