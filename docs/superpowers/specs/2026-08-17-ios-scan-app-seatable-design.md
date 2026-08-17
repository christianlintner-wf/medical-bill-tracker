# iOS-Scan-App (Phase 1: direkte SeaTable-Anbindung)

Bezug: [Issue #1 — Analyse: SeaTable-Base "Arztrechnungen" für Migration nach Java Spring + iOS-App](https://github.com/christianlintner-wf/medical-bill-tracker/issues/1)

## Kontext

Issue #1 beschreibt drei voneinander unabhängige Teilsysteme für die Ablösung von SeaTable: ein Java-Spring-Backend, ein optionales Web-Frontend und eine verpflichtende iOS-App mit Scan-Funktion. Das ist zu groß für eine einzelne Spec und wird in Teilprojekte zerlegt.

Diese Spec deckt das **erste Teilprojekt** ab: eine native iOS-App, die Arztrechnungen scannt und **direkt gegen die bestehende SeaTable-Base** arbeitet — ganz ohne eigenes Backend. SeaTable bietet dafür eine öffentliche REST-API (Row-CRUD, Datei-Upload), die für diesen Zweck ausreicht.

## Zielsetzung Phase 1

- Sofortiger Nutzen: Rechnungen unterwegs scannen statt manuell in SeaTable nachzutragen
- Kein Aufwand für Backend-Aufbau oder Datenmigration
- Architektur so gekapselt, dass ein späterer Wechsel auf ein eigenes Spring-Backend (Phase 2) nur die Netzwerk-Schicht betrifft, nicht die App-Logik/UI

## Out of Scope (spätere Phasen / andere Teilprojekte)

- Java-Spring-Backend und Datenmigration aus SeaTable (eigene Spec, falls/wenn benötigt)
- Web-Frontend (eigene Spec, optional)
- Android-/Cross-Platform-Unterstützung (aktuell nicht geplant)
- Erfassung/Bearbeitung der Tabellen Befunde, Überweisungen, KrankenkasseLeistungsbestätigung, MerkurAbrechnungsInformation (bleiben read-only über SeaTable direkt einsehbar, nicht Teil der App)
- Mehrbenutzer-Login (ein gemeinsames API-Token für den Haushalt)

## Architektur-Überblick

Native SwiftUI-App, die direkt gegen die SeaTable-REST-API arbeitet. Ein fest hinterlegtes API-Token (Keychain) authentifiziert die App gegen die Base "Arztrechnungen". Eine lokale SwiftData-Datenbank dient als Cache für Offline-Ansicht und als Outbox für noch nicht gesyncte Änderungen.

```
SwiftUI Views ── ViewModels (MVVM) ── Repository-Interface
                                            │
                                   SeaTableAPIClient (Phase 1)
                                            │
                                     SeaTable REST API

                     SwiftData: LocalCache + Outbox (Offline)
                     SyncEngine: verarbeitet Outbox bei Konnektivität
```

Die Netzwerk-Schicht ist hinter einem Repository-Interface gekapselt: ein späterer Wechsel auf ein eigenes Spring-Backend würde nur einen neuen Adapter erfordern, keine Änderung an ViewModels/UI.

### Getroffene Grundsatzentscheidungen

| Entscheidung | Wahl | Begründung |
|---|---|---|
| Plattform | Nativ Swift/SwiftUI, iOS-only | Beste Scan-/OCR-Qualität (VisionKit/Vision Framework), Android aktuell nicht geplant |
| Backend | Keins — direkt gegen SeaTable-API | Schneller Nutzen, keine Migration nötig, Repository-Interface hält Wechsel später offen |
| Auth | Ein fest hinterlegtes SeaTable-API-Token (Keychain) | Passt zur Realität: ein Collaborator-Account, kein Login-Flow nötig |
| Tabellen-Scope | Nur Arztrechnungen (voller CRUD) + Arzt (auswählen/neu anlegen) | Restliche Tabellen bleiben read-only in SeaTable, kein Bedarf für App-seitige Erfassung |
| OCR | On-device via Apple Vision Framework | Vorbefüllung von Betrag/Rechnungsnummer/Datum, offline-fähig, keine Cloud-Abhängigkeit |
| Offline-Fähigkeit | Ja, mit lokaler Warteschlange (Outbox) | Erfassung auch ohne Netz beim Arzt, automatischer Sync bei Konnektivität |
| Statusdarstellung | Horizontal-Paging-Kanban-Board | Klassisches Multi-Spalten-Kanban passt nicht auf iPhone-Breite; eine Spalte pro Screen mit Wischgeste ist der mobile Kompromiss, der dem Kanban-Gefühl am nächsten kommt |

## Komponenten

**Presentation (SwiftUI Views)**
- **Rechnungs-Board** — Horizontal-Paging-Kanban: eine Status-Spalte pro Bildschirm, seitliches Wischen zum Spaltenwechsel, Seiten-Dots als Positionsindikator. Karten zeigen Rechnungsnummer, Betrag, Arztname, Patient-Tag, Sync-Status-Icon. Drag&Drop einer Karte zum Bildschirmrand löst Auto-Scroll zur Nachbarspalte aus (Statuswechsel)
- **Rechnungsdetail/-Bearbeiten** — Felder ansehen/ändern, Status wechseln
- **Scan-Flow** — VisionKit-Scan → OCR-Vorbefüllung → Formular → Absenden
- **Arzt-Auswahl/-Neuanlage** — Picker aus Cache + "Neuen Arzt anlegen"
- **Einstellungen** — API-Token hinterlegen/prüfen

**ViewModels (MVVM)** — je View ein ViewModel (`InvoiceBoardViewModel`, `InvoiceEditViewModel`, `ScanViewModel`, `ProviderPickerViewModel`), sprechen nur mit dem Repository-Interface, kennen SeaTable nicht direkt.

**Data Layer**
- `SeaTableAPIClient` — URLSession-Wrapper: Row-CRUD, Link-Feld-Updates, Datei-Upload
- `LocalStore` (SwiftData) — gecachte Arztrechnungen-/Arzt-Zeilen + Outbox-Tabelle für ausstehende Änderungen
- `SyncEngine` — arbeitet die Outbox ab, ruft `SeaTableAPIClient`, Retry mit exponentiellem Backoff
- `OCRService` — Vision-Framework-Wrapper, extrahiert Betrag-/Datum-/Rechnungsnummer-Kandidaten aus erkanntem Text
- `ScanService` — VisionKit-Wrapper, liefert Multi-Page-Scan als zusammengeführtes PDF

## Referenz-Datenmodell (SeaTable, Ausschnitt für Phase 1)

Aus der Analyse in Issue #1 relevant für die App:

**Arztrechnungen** (Status-Werte für die Board-Spalten): `Offen → Krankenkasse eingereicht → Krankenkasse abgeschlossen → Merkur eingereicht → Merkur abgeschlossen → Erledigt`

Von der App gelesene/geschriebene Felder: Rechnungsnummer, Arztrechnung (Datei), Betrag, Patient (Select: Christian/Melanie), Arzt (Link), Status (Select). Die Felder Krankenkasse-/Merkur-Auszahlungsbetrag und Betrag Offen sind serverseitige Formel-/Lookup-Felder und werden von der App nur gelesen, nie geschrieben.

**Arzt**: ArztID, Arztname — von der App gelesen (Picker) und neue Zeilen angelegt.

## Datenfluss

### Scan-Flow (neue Rechnung)

1. "+" auf dem Board → VisionKit-Scanner öffnet Kamera
2. Multi-Page-Scan wird zu PDF zusammengeführt; `OCRService` extrahiert Text-Kandidaten
3. Formular öffnet sich vorausgefüllt (Betrag/Rechnungsnummer/Datum als Vorschlag, editierbar), Arzt-Picker (aus Cache, mit "Neu anlegen"-Option), Patient-Auswahl, Status default "Offen"
4. "Speichern" → sofort lokal in SwiftData (Status: *pending sync*), PDF lokal abgelegt, Karte erscheint sofort im Board (mit Sync-Icon)
5. `SyncEngine` sendet im Hintergrund:
   a. Falls Arzt neu ist → zuerst Arzt-Row anlegen, RowID cachen
   b. Arztrechnung-Row anlegen (mit Link zu Arzt-RowID)
   c. PDF hochladen, Datei-Feld verknüpfen
6. Erfolg → lokaler Eintrag als *synced* markiert; Fehler → bleibt in Outbox, Retry bei Netz-Wiederkehr/App-Start

### Drag&Drop-Statuswechsel

1. Karte wird auf eine andere Spalte gezogen (bzw. zum Bildschirmrand für Auto-Scroll zur Nachbarspalte)
2. Lokal sofort optimistisch aktualisiert (Karte wandert direkt visuell), Update landet in der Outbox
3. `SyncEngine` sendet Status-Update als SeaTable-Row-Update; bei Fehler bleibt Outbox-Eintrag, Karte zeigt Sync-Icon bis bestätigt

### Board-Aufbau (Lesen)

1. App lädt beim Start/Pull-to-Refresh Arztrechnungen + Arzt aus SeaTable, aktualisiert lokalen Cache
2. Board gruppiert lokal nach Status-Feld; gemergte Sicht aus Server-Daten + noch nicht gesyncten lokalen Änderungen

## Fehlerbehandlung

- **Netzwerkfehler beim Sync:** Eintrag bleibt in der Outbox, exponentielles Retry-Backoff, sichtbares Sync-Icon auf der Karte bis bestätigt
- **SeaTable-API-Fehler** (ungültiges Token, Rate-Limit): Fehlermeldung im UI, Token-Check in den Einstellungen
- **OCR liefert falsche/keine Werte:** Felder bleiben nur Vorschlag — Nutzer muss vor dem Speichern bestätigen, keine automatische Übernahme ohne Sichtprüfung
- **Konfliktfall** (Eintrag wurde zwischenzeitlich direkt in SeaTable geändert, während lokale Änderung noch offen ist): "Server gewinnt"-Strategie für Phase 1 (einfachste Lösung bei einem Account) — lokale Änderung wird verworfen, Nutzer bekommt einen Hinweis
- **Datei-Upload-Fehler:** unabhängig vom Row-Erstellen retry-fähig — Row kann bereits ohne Anhang existieren, PDF wird nachgereicht sobald der Upload klappt
- **Drag&Drop auf leere/ungültige Spalte:** kein-Op, Karte springt zur Ausgangsposition zurück

## Testing

- **Unit Tests:** `OCRService` (Textmuster-Erkennung an Beispieltexten/-scans), `SyncEngine` (Outbox-Verarbeitung, Retry-Logik, Konfliktfall) gegen gemockten `SeaTableAPIClient`
- **Integration Tests:** `SeaTableAPIClient` gegen eine separate Test-Base/Sandbox-Token für Row-CRUD und File-Upload (nicht gegen die echte Arztrechnungen-Base)
- **UI Tests (XCUITest):** Scan-Formular-Validierung, Drag&Drop-Statuswechsel auf dem Board, Arzt-Neuanlage-Flow
- **Manuelles Testen:** echter Kamera-Scan auf Gerät (Simulator hat keine Kamera)

## Entscheidungen zu späteren Phasen

- **Spring-Backend-Migration:** nicht kurzfristig geplant, sicher nicht im nächsten Jahr. Das Repository-Interface hält die Option offen, ist aber kein aktiver Fahrplanpunkt.
- **Web-Frontend:** ebenfalls nicht kurzfristig geplant.
- **Android:** nicht benötigt — die native-Swift/SwiftUI-Entscheidung bleibt damit endgültig, keine Cross-Platform-Neubewertung nötig.
