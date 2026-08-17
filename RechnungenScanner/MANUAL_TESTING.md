# Manueller Testplan — RechnungenScanner Phase 1

Auf einem echten iPhone durchführen (Simulator hat keine Kamera).

## Einrichtung
- [ ] App-Start ohne gespeichertes Token zeigt die Einstellungen-Ansicht
- [ ] Ein SeaTable-Base-API-Token für die Base "Arztrechnungen" eintragen und speichern
- [ ] Nach dem Speichern erscheint das Rechnungs-Board

## Scan-Flow
- [ ] "+" öffnet die Kamera (VisionKit-Scanner)
- [ ] Eine echte Arztrechnung fotografieren (Mehrseiten-Scan testen: 2 Seiten)
- [ ] Nach dem Scan öffnet sich das Formular vorausgefüllt (Betrag/Rechnungsnummer/Datum, wo im Dokument vorhanden)
- [ ] Vorbefüllte Werte vor dem Speichern korrigieren funktioniert
- [ ] Neuen Arzt anlegen funktioniert und ist danach im Picker auswählbar
- [ ] Nach "Speichern" erscheint die Karte sofort im Board mit "Wartet auf Sync"
- [ ] Nach kurzer Zeit (oder App-Neustart) verschwindet das Sync-Icon und der Eintrag ist in SeaTable sichtbar (inkl. hochgeladenem PDF)

## Board & Statuswechsel
- [ ] Seitliches Wischen wechselt zwischen den 6 Status-Spalten
- [ ] Eine Karte per Drag&Drop in die Nachbarspalte ziehen ändert den Status sofort lokal
- [ ] Der Statuswechsel ist nach Sync auch in SeaTable direkt sichtbar
- [ ] Tippen auf eine Karte öffnet die Detailansicht mit korrekten Werten

## Offline-Verhalten
- [ ] Flugmodus aktivieren, neue Rechnung scannen und speichern → Karte erscheint mit Sync-Icon, kein Absturz
- [ ] Flugmodus deaktivieren → Eintrag synct automatisch (spätestens beim nächsten App-Vordergrund-Wechsel)
- [ ] Statuswechsel im Flugmodus verhält sich ebenso (optimistisches Update, späterer Sync)

## Fehlerfälle
- [ ] Ungültiges Token in den Einstellungen eintragen → sinnvolle Fehlermeldung, keine Endlos-Ladeanimation
- [ ] Sync-Fehler (z. B. abgelaufenes Token) wird auf dem Einstellungen-Screen angezeigt

## Bekannte Einschränkungen dieser Phase
- Nur Arztrechnungen + Arzt sind in der App bearbeitbar; alle anderen Tabellen bleiben SeaTable-only.
- Kein Multi-User-Login — ein gemeinsames API-Token für den Haushalt.
- "Server gewinnt" bei Konflikten — keine manuelle Konfliktauflösung in Phase 1.
