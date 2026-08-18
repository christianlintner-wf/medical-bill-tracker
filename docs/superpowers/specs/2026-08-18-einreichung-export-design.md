# Einreichungs-Export (Teilprojekt A: Datei-Export)

Bezug: [Issue #7 — Einreichungs-Workflow: Rechnung/Befund für Sozialversicherung & Merkur vorbereiten (Brainstorming)](https://github.com/christianlintner-wf/medical-bill-tracker/issues/7)

## Kontext

Issue #7 sammelt vier Ideen zur Vereinfachung des Einreichungs-Workflows (ÖGK, danach Merkur). Das Thema ist zu groß für eine einzelne Spec und wird in drei Teilprojekte zerlegt:

- **A. Datei-Export** (diese Spec) — Rechnung/Befund aus der App heraus für die Einreichung vorbereiten
- **B. ÖGK-Bescheid-Abhängigkeit** — Merkur-Paket automatisch mit ÖGK-Bescheid anreichern (setzt voraus, dass geklärt wird, wie der Bescheid ins System kommt; hängt an der in Issue #1 getroffenen Scope-Entscheidung, `KrankenkasseLeistungsbestätigung`/`MerkurAbrechnungsInformation` read-only zu lassen)
- **C. Status-Historie & Reminder** — Zeitstempel pro Statuswechsel, Erinnerungslogik

Diese Spec deckt **nur Teilprojekt A** ab.

Aktuell lädt ein externes Script Rechnungsdaten in ein geshartes iCloud-Verzeichnis herunter, von dem aus der User sie manuell bei ÖGK und Merkur hochlädt. Eine direkte API-Anbindung an beide Portale ist nicht möglich — die eigentliche Einreichung bleibt ein manueller Schritt im jeweiligen Web-Portal. Ziel dieser Spec ist es, die Datei-Vorbereitung in die App zu verlagern, sodass das Sharen des iCloud-Verzeichnisses entfällt, und den Weg von der App bis zum Upload-Dialog im Portal so kurz wie möglich zu machen.

## Out of Scope

- Begleitdaten per Copy-Paste (ursprünglich Idee 2) — explizit nicht gewünscht
- PDF-Zusammenführung von Rechnung und Befund — bleiben zwei getrennte Dateien
- ÖGK-Bescheid-Handling (Teilprojekt B)
- Status-Historie/Zeitstempel/Reminder (Teilprojekt C) — der Export-Button ändert den Status **nicht** automatisch; das bleibt über den bestehenden Status-Picker/Drag&Drop
- Automatisches Abrufen von Dokumenten von ÖGK/Merkur (keine API verfügbar, kein Login-Automatismus)

## Grundsatzentscheidungen

| Entscheidung | Wahl | Begründung |
|---|---|---|
| Export-Ziel | Ein einziger, in den Einstellungen frei wählbarer Ordner (Security-Scoped Bookmark) | Ersetzt das geshartte iCloud-Verzeichnis; kann weiterhin auf iCloud Drive zeigen, muss aber nicht mehr geteilt werden, da nur die App selbst schreibt |
| Rechnung/Befund | Zwei getrennte Dateien, kein PDF-Merge | Explizite User-Vorgabe |
| Button-Logik | Ein statusabhängiger Button (Ziel ergibt sich aus `InvoiceStatus`) | Passt zum bestehenden Status-Flow, kein zusätzlicher Auswahldialog |
| Begleitdaten-Copy | Entfällt komplett | Explizite User-Vorgabe |
| Portal-Zugang | Pro `Patient` je eine hinterlegte URL für ÖGK und Merkur, öffnet in Safari | Erspart Suchen/Bookmarks im Browser; pro Patient, da Familienmitglieder ggf. unterschiedliche Portal-/Login-Links haben |
| Schneller Ordner-Zugriff beim Upload | Ordner kurz in der Dateien-App öffnen, bevor zu Safari gewechselt wird | iOS zeigt zuletzt in der Dateien-App besuchte Orte auch im System-Datei-Picker (den Safari beim Datei-Upload öffnet) unter "Zuletzt" — das ist der einzige verlässliche Weg, einen fremden Upload-Dialog zu beeinflussen, da keine Deep-Link-Kontrolle über Safari/Fremdportale besteht |

## Datenmodell-Änderung

`Invoice` hat aktuell **kein Datumsfeld** — OCR extrahiert zwar ein Datum (`ExtractedInvoiceFields.date`), aber `ScanViewModel.applyExtractedFields` verwirft es. Ohne Datum ist weder der Dateiname noch die Jahres-Unterordnerstruktur sinnvoll möglich.

- `Invoice.date: Date?` neu ergänzen (`RechnungenKit/Sources/RechnungenKit/Models/Invoice.swift`)
- `ScanViewModel.applyExtractedFields` übernimmt `fields.date` zusätzlich zu `invoiceNumber`/`amount`
- `InvoiceFormView` bekommt ein Datumsfeld (`DatePicker`), damit der Wert korrigierbar ist, falls OCR das Datum nicht erkennt — ohne manuelle Korrekturmöglichkeit wäre der Export bei fehlgeschlagener OCR blockiert
- Neue SeaTable-Spalte "Datum" in der Tabelle `Arztrechnungen`; Mapping analog zu den bestehenden Feldern in `SeaTableRow.swift`/`SeaTableInvoiceRepository.swift`

## Einstellungen

**Einreichungs-Ordner**
- Neuer Eintrag in den App-Einstellungen: zeigt aktuell konfigurierten Ordner (Name) oder "Nicht konfiguriert"
- Tap öffnet `UIDocumentPickerViewController` im Ordner-Auswahlmodus
- Nach Auswahl wird ein Security-Scoped Bookmark erzeugt (`URL.bookmarkData(options: .minimalBookmark)` bzw. passende Optionen für persistenten Zugriff) und in `UserDefaults` gespeichert
- Jeder Zugriff (Export, Ordner öffnen) klammert sich um `startAccessingSecurityScopedResource()`/`stopAccessingSecurityScopedResource()`

**Patienten-Links**
- Neue Settings-Sektion "Patienten-Links": pro `Patient`-Fall (Christian, Melanie, Theresa, Kathi, Sarah) zwei Textfelder: ÖGK-Link, Merkur-Link
- Persistiert lokal (Codable-Dictionary `[Patient: PatientLinks]` in `UserDefaults`), kein SeaTable-Sync — reine Geräte-/App-Konfiguration
- `struct PatientLinks: Codable { var oegkURL: URL?; var merkurURL: URL? }`

## Export-Logik

Neues Modul `SubmissionExportService` in `RechnungenKit` mit der Kernfunktion:

```
func export(invoice: Invoice, target: InsuranceTarget) throws -> URL   // liefert den Zielordner
```

**Statusabhängiges Button-Mapping** (`InvoiceDetailView`):

| `InvoiceStatus` | Button-Label | Ziel-Unterordner | Portal-Link |
|---|---|---|---|
| `open`, `submittedToPublicInsurance` | „Für ÖGK vorbereiten" | `<Ordner>/<Jahr>/ÖGK/` | ÖGK-Link des Patienten |
| `publicInsuranceCompleted` | „Für Merkur vorbereiten" | `<Ordner>/<Jahr>/Merkur/` | Merkur-Link des Patienten |
| `submittedToPrivateInsurance`, `privateInsuranceCompleted`, `done` | kein Button | – | – |

`<Jahr>` = Jahr von `invoice.date`.

**Dateibenennung** (pro Datei, Sonderzeichen aus Patient/Arztname entfernt, Komma im Betrag durch `-` ersetzt):

```
<YYYY-MM-DD>_<Patient>_<Arzt>_<Betrag>EUR_Rechnung.pdf
<YYYY-MM-DD>_<Patient>_<Arzt>_<Betrag>EUR_Befund.pdf   (nur falls Befund vorhanden, vgl. #6)
```

Erneutes Antippen des Buttons überschreibt die vorhandene Datei (deterministischer Name, kein Duplikat-Handling nötig).

**UI-Ablauf pro Rechnung** (in `InvoiceDetailView`, drei Buttons nebeneinander/untereinander, je nach Status wie oben befüllt):

1. „Für ÖGK/Merkur vorbereiten" — kopiert Rechnung (+ Befund) in den passenden Unterordner
2. „Ordner öffnen" — öffnet denselben Unterordner in der Dateien-App (siehe unten)
3. „Bei ÖGK/Merkur öffnen" — öffnet die für den Patienten hinterlegte URL in Safari

**Ordner öffnen:** Der aufgelöste Ordner-URL wird in eine `shareddocuments://`-URL umgewandelt und per `UIApplication.shared.open(_:)` an die Dateien-App übergeben. Zweck ist nicht primär die Ansicht selbst, sondern dass iOS diesen Ort danach unter "Zuletzt" im System-weiten Datei-Picker vorschlägt (den Safari beim Datei-Upload im Portal öffnet).

## Fehlerfälle

| Fall | Verhalten |
|---|---|
| Kein Einreichungs-Ordner konfiguriert | Alle drei Buttons zeigen einen Hinweis mit Link zu den Einstellungen statt zu exportieren |
| Bookmark ungültig (Ordner gelöscht/verschoben/Zugriff entzogen) | Fehlermeldung, Aufforderung den Ordner in den Einstellungen neu zu wählen |
| `invoice.date` ist `nil` | Export-Button deaktiviert mit Hinweis „Datum in der Rechnung ergänzen" |
| Kein Link für Patient+Ziel-Portal hinterlegt | „Bei ÖGK/Merkur öffnen"-Button ausgeblendet, kein Fehler |
| Kein Befund vorhanden | Befund-Datei wird stillschweigend übersprungen (Befund ist laut #6 optional) |
| `localPDFFileName` fehlt | Sollte nicht vorkommen (Pflichtfeld beim Scan); Export-Button in diesem Fall ausgeblendet |

## Testing

- Unit-Tests (`RechnungenKitTests`): Dateiname-Generierung inkl. Sonderzeichen-Bereinigung, Zielordner-Pfadaufbau (`<Ordner>/<Jahr>/<Portal>/`), Status→Ziel-Mapping, Verhalten bei fehlendem Datum/Befund
- Unit-Tests für Bookmark-Auflösung mit gemocktem Fehlerfall (ungültiges Bookmark)
- Manueller Testfall in `MANUAL_TESTING.md`: Ordner in Einstellungen wählen → Rechnung exportieren → „Ordner öffnen" → Safari-Link öffnen → im Portal-Upload-Dialog prüfen, dass der Ordner unter „Zuletzt" erscheint (nicht automatisierbar, da System-Picker/Fremd-Website involviert)
