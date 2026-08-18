# iPad: Sheets in voller Höhe (Teilprojekt A von #9)

Bezug: [Issue #9 — iPad-Vollwertigkeit & Mac-Unterstützung (Brainstorming)](https://github.com/christianlintner-wf/medical-bill-tracker/issues/9)

## Kontext

Issue #9 sammelt Ideen für eine vollwertige iPad-App und optionale Mac-Unterstützung. Das Thema wird in zwei unabhängige Teilprojekte zerlegt:

- **A. iPad-Anpassungen** (diese Spec)
- **B. Mac-Unterstützung** — eigene Spec, sobald der Scan-Ersatz für `VNDocumentCameraViewController` (auf Mac Catalyst nicht verfügbar) geklärt ist

Diese Spec deckt **nur Teilprojekt A** ab, und innerhalb dessen nur einen einzelnen, klar abgegrenzten Punkt: die Größe der modalen Sheets auf dem iPad.

Recherche im Rahmen des Brainstormings hat gezeigt, dass der App fast keine iPad-spezifischen Probleme hat: `TARGETED_DEVICE_FAMILY = "1,2"` ist bereits gesetzt, und es gibt keine hartkodierten `.frame(width:)`-, `GeometryReader`- oder `UIScreen.main`-Aufrufe außerhalb von `InvoiceBoardView` (dessen Spaltenlayout laut Entscheidung unten explizit Issue #8 überlassen bleibt). Der einzige sichtbare Unterschied zwischen iPhone und iPad ist heute, dass SwiftUIs `.sheet(...)` auf dem iPad standardmäßig als kleinere, zentrierte Karte erscheint statt wie auf dem iPhone die volle Bildschirmhöhe einzunehmen.

## Out of Scope

- Board-Spaltenlayout (`InvoiceBoardView`) — bleibt Issue #8 vorbehalten, auch wenn `width * 0.85`-Sizing auf großen Screens nicht ideal aussieht
- `NavigationSplitView`/Sidebar-Navigation — laut Entscheidung im Brainstorming bewusst nicht Teil dieser Spec; die App bleibt einspaltig navigierbar, auch auf dem iPad
- Explizite Tastaturkürzel (Cmd+N, Cmd+, etc.) und Pointer-/Trackpad-Feintuning — SwiftUIs Standardverhalten reicht für jetzt
- Multitasking-/Resize-Korrektheit als eigener Arbeitsblock — durch die Grep-Recherche oben bereits verifiziert, dass es (außerhalb des Boards, siehe #8) keine fixen Breiten gibt, die bei Split View/Slide Over/Stage Manager brechen könnten
- Mac-Unterstützung (Teilprojekt B, eigene künftige Spec)
- Neue Schließen-/Abbrechen-Buttons in `InvoiceDetailView`/`SettingsView` — durch die gewählte Lösung (siehe unten) nicht nötig

## Grundsatzentscheidungen

| Entscheidung | Wahl | Begründung |
|---|---|---|
| Sheet-Darstellung auf iPad | `.presentationDetents([.large])`, angewendet nur wenn `UIDevice.current.userInterfaceIdiom == .pad` | Sieht optisch wie iPhones volle Höhe aus, behält aber die native Swipe-to-Dismiss-Geste — `InvoiceDetailView` und `SettingsView` haben aktuell **keinen** Schließen-Button und werden ausschließlich per Wischgeste geschlossen; ein Wechsel zu `.fullScreenCover` würde diese Geste entfernen und Nutzer ohne Ausweg zurücklassen, sofern nicht zusätzlich neue Buttons eingebaut werden |
| Erkennung iPad vs. iPhone | `UIDevice.current.userInterfaceIdiom` statt `horizontalSizeClass` | `horizontalSizeClass` kann auf dem iPad in schmalem Split View/Slide Over `.compact` sein; das Verhalten soll aber unabhängig von der aktuellen Multitasking-Breite konsistent für iPad gelten |
| Board-Layout | Unverändert, keine Splitview/Sidebar | Explizite Entscheidung im Brainstorming: einspaltige Navigation bleibt, Board-Redesign gehört zu #8 |

## Umsetzung

Neue kleine `View`-Extension, z. B. `RechnungenScanner/RechnungenScanner/Views/View+IPadPresentation.swift`:

```swift
extension View {
    @ViewBuilder
    func iPadFullHeightSheet() -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.presentationDetents([.large])
        } else {
            self
        }
    }
}
```

Anwendungsstellen (4, alle bereits identifiziert) — jeweils `.iPadFullHeightSheet()` direkt an den Sheet-Content angehängt:

1. `RechnungenScannerApp.swift` — `.sheet(item: $scanFlowStep)` (deckt sowohl `.scanning` als auch `.reviewing`/`ScanReviewFlow` ab)
2. `RechnungenScannerApp.swift` — `.sheet(item: $selectedInvoice)` → `InvoiceDetailView`
3. `RechnungenScannerApp.swift` — `.sheet(isPresented: $isShowingSettings)` → `SettingsView`
4. `InvoiceFormView.swift:59` — `.sheet(isPresented: $isScanningFinding)` → verschachtelter Befund-Scan (`ScanFlowView`)

## Fehlerbehandlung

Keine — reine Präsentations-/Styling-Änderung, kein neuer State, kein neuer Fehlerfall.

## Testing

Kein UI-Test-Target vorhanden. Manuelle Verifikation im iPad-Simulator:

- Rechnung scannen (Flow 1) → Sheet nimmt volle Höhe ein
- Rechnungsdetail öffnen (Flow 2) → volle Höhe, Wischgeste schließt weiterhin
- Einstellungen öffnen (Flow 3) → volle Höhe, Wischgeste schließt weiterhin
- Beim Scannen einer neuen Rechnung zusätzlich Befund scannen (Flow 4, verschachteltes Sheet) → ebenfalls volle Höhe
- iPhone-Simulator gegenprüfen: Verhalten unverändert (weiterhin volle Höhe wie bisher, da Modifier dort ein No-op ist)
