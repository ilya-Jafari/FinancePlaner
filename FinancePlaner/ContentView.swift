// ============================================================
//  SmartInvest Planner – ContentView.swift
//  Senior iOS Engineer & Fintech Expert Build
//
//  Requires: iOS 17+, Swift 5.9+, Xcode 15+
//  Frameworks: SwiftUI, Charts, Observation
//
//  Architecture:
//    • FinanceModel  – @Observable state container
//    • InvestmentEngine – pure-function service layer
//    • Views          – Dashboard · Expenses · Investment
// ============================================================

import SwiftUI
import Charts

// ============================================================
// MARK: - Domain Enums
// ============================================================

/// Drei Risikostufen bestimmen die komplette Portfolio-Logik
enum RiskProfile: String, CaseIterable, Identifiable {
    case conservative = "Konservativ"
    case balanced     = "Ausgewogen"
    case progressive  = "Progressiv"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .conservative: "shield.fill"
        case .balanced:     "scale.3d"
        case .progressive:  "flame.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .conservative: .blue
        case .balanced:     .green
        case .progressive:  .orange
        }
    }

    var description: String {
        switch self {
        case .conservative:
            "Kapitalerhalt steht im Vordergrund. Niedrige Volatilität, stabile Erträge. Geeignet für kurze Zeithorizonte oder risikoaverse Anleger."
        case .balanced:
            "Ausgewogene Mischung aus Wachstum und Sicherheit. Das ideale ETF-Kernportfolio für langfristigen Vermögensaufbau."
        case .progressive:
            "Maximales Wachstumspotenzial durch hohe Aktien- und Kryptoanteile. Hohe Schwankungen werden für bessere Renditen bewusst akzeptiert."
        }
    }
}

/// Ausgaben-Kategorien mit UI-Metadaten
enum ExpenseCategory: String, CaseIterable, Identifiable, Codable {
    case rent          = "Miete/Hypothek"
    case subscriptions = "Abonnements"
    case food          = "Lebensmittel"
    case leisure       = "Freizeit"
    case transport     = "Transport"
    case insurance     = "Versicherungen"
    case other         = "Sonstiges"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rent:          "house.fill"
        case .subscriptions: "star.fill"
        case .food:          "cart.fill"
        case .leisure:       "gamecontroller.fill"
        case .transport:     "car.fill"
        case .insurance:     "umbrella.fill"
        case .other:         "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .rent:          Color(red: 0.54, green: 0.24, blue: 0.90)
        case .subscriptions: Color(red: 0.93, green: 0.24, blue: 0.48)
        case .food:          Color(red: 1.00, green: 0.58, blue: 0.00)
        case .leisure:       Color(red: 0.20, green: 0.78, blue: 0.35)
        case .transport:     Color(red: 0.20, green: 0.60, blue: 1.00)
        case .insurance:     Color(red: 0.60, green: 0.60, blue: 0.65)
        case .other:         Color(red: 0.40, green: 0.40, blue: 0.45)
        }
    }

    /// Fixkosten = monatlich konstant (Miete, Abos, Versicherungen)
    var isFixed: Bool {
        switch self {
        case .rent, .subscriptions, .insurance: true
        default:                                 false
        }
    }
}

// ============================================================
// MARK: - Data Models
// ============================================================

struct Expense: Identifiable, Codable {
    var id       = UUID()   // var (nicht let) → Codable-Synthese funktioniert korrekt
    var category: ExpenseCategory
    var name:     String
    var amount:   Double
}

/// Einzelner Baustein im vorgeschlagenen Portfolio
struct AllocationItem: Identifiable {
    let id = UUID()
    var assetName:      String
    var percentage:     Double   // 0–100
    var expectedReturn: Double   // jährl. erwartete Rendite in %
    var color:          Color
    var rationale:      String   // Kurz-Begründung für den Nutzer
}

/// Datenpunkt für die Multi-Szenario-Projektionskurve
struct ProjectionPoint: Identifiable {
    let id       = UUID()
    var year:     Int
    var value:    Double
    var scenario: String
}

// ============================================================
// MARK: - Finance Model  (@Observable – iOS 17)
// ============================================================

// UserDefaults-Schlüssel – zentral definiert, kein Tippfehler-Risiko
private enum StorageKey {
    static let income      = "si_monthlyIncome"
    static let expenses    = "si_expenses"
    static let riskProfile = "si_riskProfile"
    static let years       = "si_projectionYears"
}

@Observable
final class FinanceModel {

    // ---- Eingaben – jede Änderung löst sofortiges Speichern aus ----

    var monthlyIncome: Double = 3_500 {
        didSet { UserDefaults.standard.set(monthlyIncome, forKey: StorageKey.income) }
    }

    var expenses: [Expense] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(expenses) {
                UserDefaults.standard.set(data, forKey: StorageKey.expenses)
            }
        }
    }

    var selectedRiskProfile: RiskProfile = .balanced {
        didSet { UserDefaults.standard.set(selectedRiskProfile.rawValue, forKey: StorageKey.riskProfile) }
    }

    var projectionYears: Int = 20 {
        didSet { UserDefaults.standard.set(projectionYears, forKey: StorageKey.years) }
    }

    // ---- Init: lädt gespeicherte Werte oder fällt auf Defaults zurück ----
    init() {
        // Einkommen
        let savedIncome = UserDefaults.standard.double(forKey: StorageKey.income)
        monthlyIncome = savedIncome > 0 ? savedIncome : 3_500

        // Ausgaben
        if let data = UserDefaults.standard.data(forKey: StorageKey.expenses),
           let saved = try? JSONDecoder().decode([Expense].self, from: data), !saved.isEmpty {
            expenses = saved
        } else {
            // Erste Nutzung: Demo-Daten einsetzen
            expenses = [
                Expense(category: .rent,          name: "Kaltmiete",           amount: 950),
                Expense(category: .subscriptions, name: "Netflix · Spotify",    amount: 28),
                Expense(category: .insurance,     name: "KV / Haftpflicht",    amount: 190),
                Expense(category: .food,          name: "Lebensmittel",        amount: 380),
                Expense(category: .transport,     name: "ÖPNV / Sprit",        amount: 120),
                Expense(category: .leisure,       name: "Freizeit & Ausgehen", amount: 200),
            ]
        }

        // Risikoprofil
        if let raw = UserDefaults.standard.string(forKey: StorageKey.riskProfile),
           let profile = RiskProfile(rawValue: raw) {
            selectedRiskProfile = profile
        }

        // Zeithorizont
        let savedYears = UserDefaults.standard.integer(forKey: StorageKey.years)
        projectionYears = savedYears > 0 ? savedYears : 20
    }

    // ---- Berechnete Eigenschaften ---------------------------

    var totalFixed: Double {
        expenses.filter { $0.category.isFixed }.map(\.amount).reduce(0, +)
    }

    var totalVariable: Double {
        expenses.filter { !$0.category.isFixed }.map(\.amount).reduce(0, +)
    }

    var totalExpenses: Double { totalFixed + totalVariable }

    /// Kerngröße: Was bleibt zum Investieren übrig?
    var netSurplus: Double { monthlyIncome - totalExpenses }

    /// Sparrate in Prozent des Bruttoeinkommens
    var savingsRate: Double {
        guard monthlyIncome > 0 else { return 0 }
        return (netSurplus / monthlyIncome) * 100
    }
}

// ============================================================
// MARK: - Investment Engine  (Pure Service Layer)
// ============================================================

enum InvestmentEngine {

    // ----------------------------------------------------------
    // Portfolio-Allokation nach Risikoprofil
    //
    // Logik-Prinzipien:
    //  • Konservativ  → Kapitalerhalt; Cash & Anleihen dominieren
    //  • Ausgewogen   → Welt-ETF als Kernposition + Puffer
    //  • Progressiv   → Aktien/Emerging/Krypto für maximales Alpha
    // ----------------------------------------------------------
    static func allocation(for profile: RiskProfile) -> [AllocationItem] {
        switch profile {

        case .conservative:
            return [
                AllocationItem(assetName: "Tagesgeld / Festgeld",
                               percentage: 40, expectedReturn: 3.8,
                               color: .blue,
                               rationale: "Sicherer Liquiditätspuffer – aktuell attraktive Zinsen"),
                AllocationItem(assetName: "Anleihen-ETF (global)",
                               percentage: 30, expectedReturn: 4.2,
                               color: Color(red: 0.0, green: 0.7, blue: 0.9),
                               rationale: "Staats- & IG-Unternehmensanleihen – stabiler Einkommensstrom"),
                AllocationItem(assetName: "MSCI World ETF",
                               percentage: 25, expectedReturn: 7.0,
                               color: .green,
                               rationale: "Globaler Aktienmarkt als moderater Wachstumsanker"),
                AllocationItem(assetName: "Kryptowährungen",
                               percentage:  5, expectedReturn: 15.0,
                               color: .orange,
                               rationale: "Kleine Krypto-Beimischung für asymmetrisches Upside"),
            ]

        case .balanced:
            return [
                AllocationItem(assetName: "MSCI World ETF",
                               percentage: 50, expectedReturn: 7.0,
                               color: .green,
                               rationale: "Kernportfolio – breit über 1.500+ Unternehmen diversifiziert"),
                AllocationItem(assetName: "Tagesgeld / Festgeld",
                               percentage: 20, expectedReturn: 3.8,
                               color: .blue,
                               rationale: "Notgroschen & Opportunitätspuffer für günstige Einstiegszeitpunkte"),
                AllocationItem(assetName: "Anleihen-ETF (global)",
                               percentage: 20, expectedReturn: 4.2,
                               color: Color(red: 0.0, green: 0.7, blue: 0.9),
                               rationale: "Volatilitätsdämpfer und Rebalancing-Reservoir"),
                AllocationItem(assetName: "Kryptowährungen",
                               percentage: 10, expectedReturn: 18.0,
                               color: .orange,
                               rationale: "BTC/ETH-Anteil für erhöhtes Wachstumspotenzial"),
            ]

        case .progressive:
            return [
                AllocationItem(assetName: "MSCI World ETF",
                               percentage: 35, expectedReturn: 7.0,
                               color: .green,
                               rationale: "Stabiles Fundament im globalen Aktienmarkt"),
                AllocationItem(assetName: "Emerging Markets ETF",
                               percentage: 20, expectedReturn: 9.5,
                               color: Color(red: 0.1, green: 0.8, blue: 0.6),
                               rationale: "Schwellenländer – höheres Wachstum durch demografischen Rückenwind"),
                AllocationItem(assetName: "Tech-Sektor / NASDAQ ETF",
                               percentage: 25, expectedReturn: 11.0,
                               color: Color(red: 0.4, green: 0.3, blue: 0.9),
                               rationale: "Gezielte Sektor-Overweight-Position in Technologie & KI"),
                AllocationItem(assetName: "Kryptowährungen",
                               percentage: 20, expectedReturn: 22.0,
                               color: .orange,
                               rationale: "Hohe Krypto-Allokation – Bitcoin / Ethereum Kern + Altcoins"),
            ]
        }
    }

    /// Gewichteter Durchschnitts-Ertrag des Portfolios
    /// = Summe( Rendite_i × Gewicht_i )
    static func weightedReturn(for items: [AllocationItem]) -> Double {
        items.reduce(0) { $0 + ($1.expectedReturn * $1.percentage / 100) }
    }

    // ----------------------------------------------------------
    // Zinseszins-Projektion (Future Value of Annuity)
    //
    //   FV = PMT × [ (1 + r)^n − 1 ] / r
    //
    //   PMT = monatliche Einzahlung (Netto-Überschuss)
    //   r   = monatlicher Zinssatz  = jahresrendite / 12
    //   n   = Anzahl Monate         = jahre × 12
    //
    // Gibt für jedes Jahr einen (Jahr, Vermögenswert)-Tupel zurück.
    // ----------------------------------------------------------
    static func projection(
        monthlyContribution pmt: Double,
        annualReturnRate annualR: Double,
        years: Int
    ) -> [(year: Int, value: Double)] {

        guard pmt > 0, years > 0 else { return [] }

        let r = annualR / 100 / 12   // monatlicher Zinssatz (dezimal)

        return (1...years).map { year in
            let n  = Double(year * 12)
            let fv: Double
            if r == 0 {
                fv = pmt * n           // kein Zinseszins-Effekt
            } else {
                fv = pmt * (pow(1 + r, n) - 1) / r
            }
            return (year: year, value: fv)
        }
    }

    // ----------------------------------------------------------
    // Multi-Szenario-Projektion
    //   Pessimistisch = Basis − 2 %
    //   Basis         = gewichtete Portfolio-Rendite
    //   Optimistisch  = Basis + 3 %
    // ----------------------------------------------------------
    static func multiScenario(
        monthlyContribution: Double,
        baseReturn: Double,
        years: Int
    ) -> [ProjectionPoint] {

        let scenarios: [(label: String, delta: Double)] = [
            ("Pessimistisch", -2.0),
            ("Basis",          0.0),
            ("Optimistisch",  +3.0),
        ]

        return scenarios.flatMap { s in
            let r = max(0, baseReturn + s.delta)
            return projection(monthlyContribution: monthlyContribution,
                              annualReturnRate: r,
                              years: years)
                .map { ProjectionPoint(year: $0.year, value: $0.value, scenario: s.label) }
        }
    }
}

// ============================================================
// MARK: - Formatting Helpers
// ============================================================

extension Double {

    /// Formatiert als Euro-Betrag (keine Nachkommastellen)
    var eur: String {
        let f = NumberFormatter()
        f.numberStyle         = .currency
        f.currencySymbol      = "€"
        f.currencyCode        = "EUR"
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "de_DE")
        return f.string(from: NSNumber(value: self)) ?? "–"
    }

    /// Kompakte Darstellung: 1.234.000 → "1,2 Mio. €"
    var eurCompact: String {
        if self >= 1_000_000 {
            return String(format: "%.1f Mio. €", self / 1_000_000)
        } else if self >= 1_000 {
            return String(format: "%.0f T€", self / 1_000)
        }
        return eur
    }

    /// Prozentwert mit einer Dezimalstelle
    var pct: String { String(format: "%.1f %%", self) }
}

// ============================================================
// MARK: - App Entry Point
// ============================================================

struct ContentView: View {
    @State private var model       = FinanceModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(model: model)
                .tabItem { Label("Dashboard",  systemImage: "house.fill") }
                .tag(0)

            ExpensesView(model: model)
                .tabItem { Label("Ausgaben",   systemImage: "list.bullet.rectangle.fill") }
                .tag(1)

            InvestmentView(model: model)
                .tabItem { Label("Investition", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(2)
        }
        .tint(.green)
    }
}

// ============================================================
// MARK: - Dashboard View
// ============================================================

struct DashboardView: View {
    @Bindable var model: FinanceModel
    @State private var showIncomeSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroCard
                    summaryStrip
                    if !model.expenses.isEmpty { donutCard }
                    savingsRateCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("SmartInvest")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showIncomeSheet = true } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .sheet(isPresented: $showIncomeSheet) {
                IncomeSheet(model: model)
            }
        }
    }

    // ── Hero ──────────────────────────────────────────────────

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Monatlicher Netto-Überschuss", systemImage: "calendar.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.netSurplus.eur)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(model.netSurplus >= 0 ? .green : .red)
                    .contentTransition(.numericText())
                    .animation(.spring, value: model.netSurplus)

                Image(systemName: model.netSurplus >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(model.netSurplus >= 0 ? .green : .red)
                    .font(.title2)
            }

            Divider().padding(.vertical, 2)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Einkommen").font(.caption).foregroundStyle(.secondary)
                    Text(model.monthlyIncome.eur).font(.headline).fontWeight(.semibold)
                }
                Spacer()
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Ausgaben").font(.caption).foregroundStyle(.secondary)
                    Text(model.totalExpenses.eur).font(.headline)
                        .foregroundStyle(.red).fontWeight(.semibold)
                }
                Spacer()
                Image(systemName: "equal.circle.fill")
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Überschuss").font(.caption).foregroundStyle(.secondary)
                    Text(model.netSurplus.eur).font(.headline)
                        .foregroundStyle(model.netSurplus >= 0 ? .green : .red)
                        .fontWeight(.bold)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    model.netSurplus >= 0
                        ? Color.green.opacity(0.35)
                        : Color.red.opacity(0.35),
                    lineWidth: 1.5
                )
        }
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    // ── 3-up Strip ────────────────────────────────────────────

    private var summaryStrip: some View {
        HStack(spacing: 12) {
            MiniCard(title: "Fixkosten",  value: model.totalFixed.eur,       icon: "lock.fill",             color: .purple)
            MiniCard(title: "Variabel",   value: model.totalVariable.eur,    icon: "arrow.up.arrow.down",   color: .orange)
            MiniCard(title: "Sparrate",   value: model.savingsRate.pct,      icon: "percent",
                     color: model.savingsRate >= 20 ? .green : (model.savingsRate >= 10 ? .yellow : .red))
        }
    }

    // ── Donut-Diagramm ────────────────────────────────────────

    private var donutCard: some View {
        SICard(title: "Ausgaben-Verteilung", icon: "chart.pie.fill") {
            VStack(spacing: 16) {
                Chart(model.expenses) { exp in
                    SectorMark(
                        angle:       .value("Betrag", exp.amount),
                        innerRadius: .ratio(0.56),
                        angularInset: 2.5
                    )
                    .foregroundStyle(exp.category.color)
                    .cornerRadius(5)
                }
                .chartBackground { _ in
                    VStack(spacing: 2) {
                        Text(model.totalExpenses.eur)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("Gesamt").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 190)

                // Legende
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(model.expenses) { exp in
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(exp.category.color)
                                .frame(width: 10, height: 10)
                            Text(exp.name).font(.caption).lineLimit(1)
                            Spacer()
                            Text(exp.amount.eur).font(.caption).fontWeight(.semibold)
                        }
                    }
                }
            }
        }
    }

    // ── Sparrate ──────────────────────────────────────────────

    private var savingsRateCard: some View {
        SICard(title: "Sparquoten-Analyse", icon: "chart.bar.fill") {
            let rate  = model.savingsRate
            let color = rateColor(rate)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(rate.pct)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(color)

                    Spacer()

                    Text(rateLabel(rate))
                        .font(.subheadline).fontWeight(.semibold)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(color.opacity(0.15), in: Capsule())
                        .foregroundStyle(color)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.15)).frame(height: 10)
                        Capsule().fill(color)
                            .frame(width: geo.size.width * min(max(rate / 50, 0), 1), height: 10)
                            .animation(.spring, value: rate)
                    }
                }
                .frame(height: 10)

                Text(rateAdvice(rate)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rateColor(_ r: Double) -> Color {
        r < 10 ? .red : r < 20 ? .orange : r < 30 ? .yellow : .green
    }
    private func rateLabel(_ r: Double) -> String {
        r < 10 ? "Kritisch" : r < 20 ? "Ausbaufähig" : r < 30 ? "Gut" : "Exzellent 🎯"
    }
    private func rateAdvice(_ r: Double) -> String {
        switch r {
        case ..<10:  "Versuche mindestens 10 % zu sparen. Überprüfe besonders die variablen Ausgaben auf Einsparpotenzial."
        case ..<20:  "Gute Basis! Mit 20 % Sparrate bist du auf dem Weg zur finanziellen Freiheit. Kleine Optimierungen helfen."
        case ..<30:  "Sehr gut! Du übertriffst den Bundesdurchschnitt. Nutze den Investment-Tab für eine optimale Anlage-Strategie."
        default:     "Hervorragend! Du bist auf dem Weg zur finanziellen Unabhängigkeit (FIRE). Maximiere jetzt deinen Zinseszins-Effekt!"
        }
    }
}

// ============================================================
// MARK: - Expenses View
// ============================================================

struct ExpensesView: View {
    @Bindable var model: FinanceModel
    @State private var showAdd = false

    // Indices der Fixkosten in model.expenses
    private var fixedIndices: [Int] {
        model.expenses.indices.filter { model.expenses[$0].category.isFixed }
    }
    private var variableIndices: [Int] {
        model.expenses.indices.filter { !model.expenses[$0].category.isFixed }
    }

    var body: some View {
        NavigationStack {
            List {
                // ---- Fixkosten -----------------------------------
                Section {
                    ForEach(fixedIndices, id: \.self) { i in
                        ExpenseRow(expense: $model.expenses[i])
                    }
                    .onDelete { offsets in
                        deleteAt(offsets: offsets, from: fixedIndices)
                    }
                } header: {
                    SectionHeader(title: "Fixkosten", total: model.totalFixed, color: .purple)
                }

                // ---- Variable Kosten -----------------------------
                Section {
                    ForEach(variableIndices, id: \.self) { i in
                        ExpenseRow(expense: $model.expenses[i])
                    }
                    .onDelete { offsets in
                        deleteAt(offsets: offsets, from: variableIndices)
                    }
                } header: {
                    SectionHeader(title: "Variable Kosten", total: model.totalVariable, color: .orange)
                }

                // ---- Zusammenfassung -----------------------------
                Section {
                    LabeledContent {
                        Text(model.totalExpenses.eur).fontWeight(.bold)
                    } label: {
                        Label("Gesamt-Ausgaben", systemImage: "sum")
                    }

                    LabeledContent {
                        Text(model.netSurplus.eur)
                            .fontWeight(.bold)
                            .foregroundStyle(model.netSurplus >= 0 ? .green : .red)
                    } label: {
                        Label("Netto-Überschuss", systemImage: "arrow.up.right.circle.fill")
                            .foregroundStyle(model.netSurplus >= 0 ? .green : .red)
                    }
                }
            }
            // Bug-Fix 2a: Scrollen schließt die Tastatur
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Ausgaben")
            // Bug-Fix 2b: "Fertig"-Button über der Tastatur
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2).foregroundStyle(.green)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddExpenseSheet(model: model)
            }
        }
    }

    private func deleteAt(offsets: IndexSet, from pool: [Int]) {
        let toRemove = offsets.map { pool[$0] }
        model.expenses.remove(atOffsets: IndexSet(toRemove))
    }
}

// ============================================================
// MARK: - Investment View
// ============================================================

struct InvestmentView: View {
    @Bindable var model: FinanceModel

    private var items: [AllocationItem] { InvestmentEngine.allocation(for: model.selectedRiskProfile) }
    private var wReturn: Double         { InvestmentEngine.weightedReturn(for: items) }

    private var projectionPoints: [ProjectionPoint] {
        guard model.netSurplus > 0 else { return [] }
        return InvestmentEngine.multiScenario(
            monthlyContribution: model.netSurplus,
            baseReturn:          wReturn,
            years:               model.projectionYears
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    riskSelector
                    if model.netSurplus <= 0 {
                        noSurplusWarning
                    } else {
                        allocationCard
                        projectionCard
                        settingsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Investment-Plan")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // ── Risiko-Selektor ───────────────────────────────────────

    private var riskSelector: some View {
        SICard(title: "Risiko-Profil wählen", icon: "dial.medium.fill") {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    ForEach(RiskProfile.allCases) { p in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                model.selectedRiskProfile = p
                            }
                        } label: {
                            VStack(spacing: 7) {
                                Image(systemName: p.icon)
                                    .font(.title2)
                                    .symbolRenderingMode(.hierarchical)
                                Text(p.rawValue)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                model.selectedRiskProfile == p
                                    ? p.accentColor
                                    : Color(.systemGray5),
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                            .foregroundStyle(
                                model.selectedRiskProfile == p ? .white : .secondary
                            )
                            .shadow(
                                color: model.selectedRiskProfile == p
                                    ? p.accentColor.opacity(0.40) : .clear,
                                radius: 8, x: 0, y: 4
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: model.selectedRiskProfile.icon)
                        .foregroundStyle(model.selectedRiskProfile.accentColor)
                    Text(model.selectedRiskProfile.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(model.selectedRiskProfile.accentColor.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // ── Portfolio-Allokation (Balkendiagramm) ─────────────────

    private var allocationCard: some View {
        SICard(title: "Portfolio-Verteilung", icon: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 18) {

                // KPIs
                HStack {
                    KPIBadge(label: "Monatlich anlegen", value: model.netSurplus.eur,  color: .green)
                    Spacer()
                    KPIBadge(label: "Ø Rendite p.a.",    value: wReturn.pct,            color: .blue, align: .trailing)
                }

                Divider()

                // Balkendiagramm
                Chart(items) { item in
                    BarMark(
                        x: .value("%", item.percentage),
                        y: .value("Asset", item.assetName)
                    )
                    .foregroundStyle(item.color)
                    .cornerRadius(7)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(Int(item.percentage)) %")
                            .font(.caption).fontWeight(.bold)
                            .foregroundStyle(item.color)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { val in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = val.as(Int.self) { Text("\(v)%").font(.caption2) }
                        }
                    }
                }
                .frame(height: CGFloat(items.count) * 62)

                Divider()

                // Detail-Liste
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.color)
                            .frame(width: 4, height: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.assetName)
                                    .font(.subheadline).fontWeight(.semibold)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text((model.netSurplus * item.percentage / 100).eur)
                                        .font(.subheadline).fontWeight(.bold)
                                        .foregroundStyle(item.color)
                                    Text("Ø \(item.expectedReturn.pct) p.a.").font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(item.rationale).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // ── Zinseszins-Projektion (Liniendiagramm) ────────────────

    private var projectionCard: some View {
        SICard(title: "Zinseszins-Projektion", icon: "chart.line.uptrend.xyaxis.circle.fill") {
            VStack(alignment: .leading, spacing: 14) {
                if projectionPoints.isEmpty {
                    ContentUnavailableView(
                        "Kein Überschuss",
                        systemImage: "exclamationmark.circle",
                        description: Text("Reduziere deine Ausgaben, um die Projektion zu sehen.")
                    )
                } else {
                    // Liniendiagramm
                    Chart(projectionPoints) { pt in
                        LineMark(
                            x: .value("Jahr", pt.year),
                            y: .value("Vermögen", pt.value)
                        )
                        .foregroundStyle(by: .value("Szenario", pt.scenario))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        AreaMark(
                            x: .value("Jahr", pt.year),
                            y: .value("Vermögen", pt.value)
                        )
                        .foregroundStyle(by: .value("Szenario", pt.scenario))
                        .opacity(0.07)
                        .interpolationMethod(.catmullRom)
                    }
                    .chartForegroundStyleScale([
                        "Pessimistisch": Color.red,
                        "Basis":         Color.blue,
                        "Optimistisch":  Color.green,
                    ])
                    .chartYAxis {
                        AxisMarks { val in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = val.as(Double.self) {
                                    Text(v.eurCompact).font(.caption2)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: stride(from: 0, through: model.projectionYears, by: 5).map { $0 }) { val in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = val.as(Int.self) { Text("J\(v)").font(.caption2) }
                            }
                        }
                    }
                    .frame(height: 230)

                    Divider()

                    // Endwerte nach N Jahren
                    Text("Prognostiziertes Vermögen nach \(model.projectionYears) Jahren:")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)

                    HStack(spacing: 0) {
                        ForEach(["Pessimistisch", "Basis", "Optimistisch"], id: \.self) { label in
                            let color: Color = label == "Pessimistisch" ? .red : label == "Basis" ? .blue : .green
                            if let pt = projectionPoints.last(where: { $0.year == model.projectionYears && $0.scenario == label }) {
                                VStack(spacing: 4) {
                                    Text(pt.value.eurCompact)
                                        .font(.callout).fontWeight(.bold)
                                        .foregroundStyle(color)
                                    Text(label).font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    // Erklärung Szenarien
                    Text("Pessimistisch: Basis −2 % | Basis: \(wReturn.pct) Ø p.a. | Optimistisch: Basis +3 %")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // ── Einstellungen (Stepper) ───────────────────────────────

    private var settingsCard: some View {
        SICard(title: "Projektions-Einstellungen", icon: "slider.horizontal.3") {
            VStack(spacing: 16) {
                HStack {
                    Label("Zeitraum", systemImage: "calendar.badge.clock")
                        .font(.subheadline)
                    Spacer()
                    Text("\(model.projectionYears) Jahre")
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundStyle(.blue)
                        .contentTransition(.numericText())
                }
                Stepper("",
                        value: $model.projectionYears,
                        in: 5...40,
                        step: 5)
                    .labelsHidden()

                Text("Der Zinseszins-Effekt entfaltet seine volle Kraft ab ca. 15 Jahren. Je länger der Zeitraum, desto größer der Wachstumssprung im letzten Drittel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ── Kein Überschuss ───────────────────────────────────────

    private var noSurplusWarning: some View {
        SICard(title: "Kein Investitions-Spielraum", icon: "exclamationmark.triangle.fill") {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
                Text("Dein monatlicher Überschuss beträgt \(model.netSurplus.eur). Reduziere deine variablen Ausgaben im Tab \"Ausgaben\", um mit dem Investieren zu beginnen.")
                    .multilineTextAlignment(.center)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

// ============================================================
// MARK: - Sheet Views
// ============================================================

struct IncomeSheet: View {
    @Bindable var model: FinanceModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Monatliches Netto-Einkommen") {
                    HStack {
                        Image(systemName: "eurosign.circle.fill").foregroundStyle(.green)
                        TextField("Betrag", value: $model.monthlyIncome, format: .currency(code: "EUR"))
                            .keyboardType(.decimalPad)
                    }
                }
                Section("Vorschau") {
                    LabeledContent("Einkommen", value: model.monthlyIncome.eur)
                    LabeledContent("Gesamtausgaben", value: model.totalExpenses.eur)
                    LabeledContent {
                        Text(model.netSurplus.eur).fontWeight(.bold)
                            .foregroundStyle(model.netSurplus >= 0 ? .green : .red)
                    } label: {
                        Text("Überschuss")
                    }
                }
            }
            .navigationTitle("Einkommen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                    .fontWeight(.semibold).foregroundStyle(.green)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

struct AddExpenseSheet: View {
    @Bindable var model: FinanceModel
    @Environment(\.dismiss) private var dismiss

    @State private var name:     String          = ""
    @State private var amount:   Double          = 0
    @State private var category: ExpenseCategory = .food

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && amount > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Bezeichnung (z.B. Fitnessstudio)", text: $name)
                    HStack {
                        Image(systemName: "eurosign").foregroundStyle(.secondary)
                        TextField("Monatlicher Betrag", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                    }
                }
                Section("Kategorie") {
                    Picker("Kategorie", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Ausgabe hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hinzufügen") {
                        model.expenses.append(Expense(category: category, name: name, amount: amount))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}

// ============================================================
// MARK: - Reusable UI Components
// ============================================================

/// Universelle Karten-Container-Komponente
struct SICard<Content: View>: View {
    let title:   String
    let icon:    String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title   = title
        self.icon    = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.headline)
                .fontWeight(.semibold)
                .symbolRenderingMode(.hierarchical)

            content
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
    }
}

/// Kleine Kennzahl-Kachel für den Summary-Strip
struct MiniCard: View {
    let title: String
    let value: String
    let icon:  String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
            Spacer(minLength: 0)
            Text(value)
                .font(.callout).fontWeight(.bold)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}

/// Sektion-Header in der Listen-Ansicht
struct SectionHeader: View {
    let title: String
    let total: Double
    let color: Color

    var body: some View {
        HStack {
            Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(color)
            Spacer()
            Text(total.eur).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Bearbeitbare Ausgaben-Zeile
struct ExpenseRow: View {
    @Binding var expense: Expense

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(expense.category.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: expense.category.icon)
                    .font(.subheadline)
                    .foregroundStyle(expense.category.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.name).font(.subheadline)
                Text(expense.category.rawValue).font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            TextField("0",
                      value: $expense.amount,
                      format: .currency(code: "EUR"))
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .font(.subheadline).fontWeight(.semibold)
                .frame(width: 100)
        }
        .padding(.vertical, 4)
    }
}

/// KPI-Badge für den Portfolio-Header
struct KPIBadge: View {
    let label: String
    let value: String
    let color: Color
    var align: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: align, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
    }
}

// ============================================================
// MARK: - Previews
// ============================================================

#Preview("Full App") {
    ContentView()
}

#Preview("Dashboard") {
    DashboardView(model: FinanceModel())
}

#Preview("Investment") {
    InvestmentView(model: FinanceModel())
}
