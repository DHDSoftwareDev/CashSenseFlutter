import AppIntents
import Foundation
import SwiftUI
import WidgetKit

private let appGroupId = "group.name.dhdsoftware.cashsense.CashSenseMM"
private let snapshotKey = "cashsense_widget_snapshot"

private struct BillItem: Codable, Identifiable {
    let id: String
    let name: String
    let note: String?
    let amount: Double
    let dueMillis: Int64
    let type: String
    let paymentStatus: String?

    var dueDate: Date {
        Date(timeIntervalSince1970: TimeInterval(dueMillis) / 1000)
    }

    var isPaid: Bool {
        paymentStatus == "paid"
    }
}

private struct AccountItem: Codable, Identifiable {
    let id: String
    let name: String
    let currency: String
    let balance: Double
    let currentBalance: Double?
}

private struct CashSenseSnapshot: Codable {
    let version: Int
    let generatedAtMillis: Int64
    let hideBalances: Bool
    let primaryColor: Int64?
    let bills: [BillItem]
    let accounts: [AccountItem]
    let totalAvailable: Double
    let totalCurrent: Double?
    let totalCurrency: String?
    let hasMixedCurrencies: Bool?

    static let empty = CashSenseSnapshot(
        version: 1,
        generatedAtMillis: 0,
        hideBalances: false,
        primaryColor: 0xFF2E7D32,
        bills: [],
        accounts: [],
        totalAvailable: 0,
        totalCurrent: 0,
        totalCurrency: "USD",
        hasMixedCurrencies: false
    )

    var widgetColor: Color {
        let argb = UInt32(truncatingIfNeeded: primaryColor ?? 0xFF2E7D32)
        return Color(
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255
        )
    }

    var widgetForegroundColor: Color {
        relativeLuminance > 0.42 ? .black : .white
    }

    private var relativeLuminance: Double {
        let argb = UInt32(truncatingIfNeeded: primaryColor ?? 0xFF2E7D32)
        func linear(_ component: UInt32) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear((argb >> 16) & 0xFF)
            + 0.7152 * linear((argb >> 8) & 0xFF)
            + 0.0722 * linear(argb & 0xFF)
    }
}

private func loadCashSenseSnapshot() -> CashSenseSnapshot {
    guard
        let raw = UserDefaults(suiteName: appGroupId)?.string(forKey: snapshotKey),
        let data = raw.data(using: .utf8),
        let snapshot = try? JSONDecoder().decode(CashSenseSnapshot.self, from: data)
    else {
        return .empty
    }
    return snapshot
}

private struct CashSenseEntry: TimelineEntry {
    let date: Date
    let snapshot: CashSenseSnapshot
}

private struct CashSenseProvider: TimelineProvider {
    func placeholder(in context: Context) -> CashSenseEntry {
        CashSenseEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (CashSenseEntry) -> Void
    ) {
        completion(CashSenseEntry(date: .now, snapshot: loadCashSenseSnapshot()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<CashSenseEntry>) -> Void
    ) {
        let snapshot = loadCashSenseSnapshot()
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: .now)
        let entries = (0...30).compactMap { offset -> CashSenseEntry? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            return CashSenseEntry(date: date, snapshot: snapshot)
        }
        let refresh = calendar.date(byAdding: .day, value: 31, to: start) ??
            Date(timeIntervalSinceNow: 86_400)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

}

@available(iOSApplicationExtension 17.0, *)
enum UpcomingBillsFilter: String, AppEnum {
    case all
    case unpaid
    case paid
    case pastDue

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bills to Show")
    static let caseDisplayRepresentations: [UpcomingBillsFilter: DisplayRepresentation] = [
        .all: DisplayRepresentation(title: "Paid and Unpaid"),
        .unpaid: DisplayRepresentation(title: "Unpaid Only"),
        .paid: DisplayRepresentation(title: "Paid Only"),
        .pastDue: DisplayRepresentation(title: "Past Due Only"),
    ]
}

@available(iOSApplicationExtension 17.0, *)
struct ConfigureUpcomingBillsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Upcoming Bills"
    static let description = IntentDescription(
        "Choose which paid, unpaid, or past-due bills appear."
    )

    @Parameter(title: "Bills to Show", default: .unpaid)
    var billFilter: UpcomingBillsFilter

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$billFilter)")
    }
}

@available(iOSApplicationExtension 17.0, *)
private struct UpcomingBillsEntry: TimelineEntry {
    let date: Date
    let snapshot: CashSenseSnapshot
    let billFilter: UpcomingBillsFilter
}

@available(iOSApplicationExtension 17.0, *)
private struct UpcomingBillsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UpcomingBillsEntry {
        UpcomingBillsEntry(date: .now, snapshot: .empty, billFilter: .unpaid)
    }

    func snapshot(
        for configuration: ConfigureUpcomingBillsIntent,
        in context: Context
    ) async -> UpcomingBillsEntry {
        entry(for: configuration, date: .now)
    }

    func timeline(
        for configuration: ConfigureUpcomingBillsIntent,
        in context: Context
    ) async -> Timeline<UpcomingBillsEntry> {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: .now)
        let entries = (0...30).compactMap { offset -> UpcomingBillsEntry? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            return entry(for: configuration, date: date)
        }
        let refresh = calendar.date(byAdding: .day, value: 31, to: start) ??
            Date(timeIntervalSinceNow: 86_400)
        return Timeline(entries: entries, policy: .after(refresh))
    }

    private func entry(
        for configuration: ConfigureUpcomingBillsIntent,
        date: Date
    ) -> UpcomingBillsEntry {
        UpcomingBillsEntry(
            date: date,
            snapshot: loadCashSenseSnapshot(),
            billFilter: configuration.billFilter
        )
    }
}

@available(iOSApplicationExtension 17.0, *)
struct WidgetAccount: AppEntity {
    static let allAccountsID = "__all_accounts__"
    static let allAccounts = WidgetAccount(
        id: allAccountsID,
        name: "All Accounts",
        currency: "Combined view"
    )

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Account")
    static let defaultQuery = WidgetAccountQuery()

    let id: String
    let name: String
    let currency: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: LocalizedStringResource(stringLiteral: currency)
        )
    }
}

@available(iOSApplicationExtension 17.0, *)
struct WidgetAccountQuery: EntityQuery {
    func entities(for identifiers: [WidgetAccount.ID]) async throws -> [WidgetAccount] {
        let identifiers = Set(identifiers)
        return selectableAccounts().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetAccount] {
        selectableAccounts()
    }

    func defaultResult() async -> WidgetAccount? {
        .allAccounts
    }

    private func selectableAccounts() -> [WidgetAccount] {
        [.allAccounts] + loadCashSenseSnapshot().accounts.map {
            WidgetAccount(id: $0.id, name: $0.name, currency: $0.currency)
        }
    }
}

@available(iOSApplicationExtension 17.0, *)
enum WidgetBalanceType: String, AppEnum {
    case available
    case current

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Balance Type")
    static let caseDisplayRepresentations: [WidgetBalanceType: DisplayRepresentation] = [
        .available: DisplayRepresentation(title: "Available Balance"),
        .current: DisplayRepresentation(title: "Current Balance"),
    ]
}

@available(iOSApplicationExtension 17.0, *)
struct SelectBalanceAccountIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Account Balance"
    static let description = IntentDescription("Choose the accounts and balance type shown in this widget.")

    @Parameter(title: "Accounts")
    var accounts: [WidgetAccount]?

    @Parameter(title: "Balance Type", default: .available)
    var balanceType: WidgetBalanceType

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$balanceType) for \(\.$accounts)")
    }
}

@available(iOSApplicationExtension 17.0, *)
private struct AccountBalancesEntry: TimelineEntry {
    let date: Date
    let snapshot: CashSenseSnapshot
    let selectedAccountIDs: [String]?
    let balanceType: WidgetBalanceType
}

@available(iOSApplicationExtension 17.0, *)
private struct AccountBalancesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AccountBalancesEntry {
        AccountBalancesEntry(
            date: .now,
            snapshot: .empty,
            selectedAccountIDs: nil,
            balanceType: .available
        )
    }

    func snapshot(
        for configuration: SelectBalanceAccountIntent,
        in context: Context
    ) async -> AccountBalancesEntry {
        entry(for: configuration, date: .now)
    }

    func timeline(
        for configuration: SelectBalanceAccountIntent,
        in context: Context
    ) async -> Timeline<AccountBalancesEntry> {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: .now)
        let entries = (0...30).compactMap { offset -> AccountBalancesEntry? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            return entry(for: configuration, date: date)
        }
        let refresh = calendar.date(byAdding: .day, value: 31, to: start) ??
            Date(timeIntervalSinceNow: 86_400)
        return Timeline(entries: entries, policy: .after(refresh))
    }

    private func entry(
        for configuration: SelectBalanceAccountIntent,
        date: Date
    ) -> AccountBalancesEntry {
        let selectedIDs = configuration.accounts?.map(\.id)
        let showsAllAccounts = selectedIDs?.contains(WidgetAccount.allAccountsID) == true
        return AccountBalancesEntry(
            date: date,
            snapshot: loadCashSenseSnapshot(),
            selectedAccountIDs: selectedIDs?.isEmpty == false && !showsAllAccounts
                ? selectedIDs
                : nil,
            balanceType: configuration.balanceType
        )
    }
}

private extension View {
    @ViewBuilder
    func cashSenseWidgetBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { color }
        } else {
            background(color)
        }
    }
}

private struct WidgetHeader: View {
    let title: String
    let summary: String
    let foreground: Color
    var stacksVertically = false

    var body: some View {
        Group {
            if stacksVertically {
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    summaryText
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    titleText
                    Spacer(minLength: 4)
                    summaryText
                }
            }
        }
        // Bill rows can use two lines. Keep the header from being collapsed
        // when their combined ideal height is taller than the widget.
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }

    private var titleText: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(foreground)
            .lineLimit(1)
    }

    private var summaryText: some View {
        Text(summary)
            .font(.caption.bold())
            .foregroundStyle(foreground.opacity(0.78))
            .lineLimit(1)
    }
}

@available(iOSApplicationExtension 17.0, *)
private struct UpcomingBillsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingBillsEntry

    private var visibleBills: [BillItem] {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: entry.date)
        return entry.snapshot.bills
            .filter { bill in
                let due = calendar.startOfDay(for: bill.dueDate)
                let isPastDue = due < start

                switch entry.billFilter {
                case .all:
                    return !isPastDue
                case .unpaid:
                    return !isPastDue && !bill.isPaid
                case .paid:
                    return !isPastDue && bill.isPaid
                case .pastDue:
                    return isPastDue && !bill.isPaid
                }
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var billsDueThisMonth: Int {
        let calendar = Calendar.autoupdatingCurrent
        return visibleBills.filter { bill in
            calendar.isDate(bill.dueDate, equalTo: entry.date, toGranularity: .month)
        }.count
    }

    private var billSummary: String {
        if entry.billFilter == .pastDue {
            return "Past due - \(visibleBills.count) bills"
        }
        let month = entry.date.formatted(.dateTime.month(.wide))
        return "\(month) - \(billsDueThisMonth) bills due"
    }

    private var emptyMessage: String {
        switch entry.billFilter {
        case .all: return "No upcoming bills"
        case .unpaid: return "No upcoming unpaid bills"
        case .paid: return "No upcoming paid bills"
        case .pastDue: return "No past-due bills"
        }
    }

    private var rowLimit: Int {
        switch family {
        case .systemSmall: return 2
        case .systemLarge: return 6
        default: return 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(
                title: "Upcoming Bills",
                summary: billSummary,
                foreground: entry.snapshot.widgetForegroundColor,
                stacksVertically: family == .systemSmall
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(entry.snapshot.widgetColor)

            VStack(alignment: .leading, spacing: 8) {
                if visibleBills.isEmpty {
                    Spacer()
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    let displayedBills = Array(visibleBills.prefix(rowLimit))
                    ForEach(Array(displayedBills.enumerated()), id: \.element.id) { index, bill in
                        Link(destination: billURL(bill)) {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(bill.name).font(.caption.bold()).lineLimit(1)
                                    if let note = bill.note, !note.isEmpty {
                                        Text(note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 4)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(bill.amount, format: .currency(code: "USD"))
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(bill.isPaid ? "Paid · \(dueText(bill.dueDate))" : dueText(bill.dueDate))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        if index < displayedBills.count - 1 {
                            Divider()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cashSenseWidgetBackground(Color(.systemBackground))
        .widgetURL(visibleBills.first.map(billURL) ?? URL(string: "cashsense://bills")!)
    }

    private func billURL(_ bill: BillItem) -> URL {
        URL(string: "cashsense://bills?date=\(bill.dueMillis)")!
    }

    private func dueText(_ date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let due = calendar.startOfDay(for: date)
        let current = calendar.startOfDay(for: entry.date)
        let days = calendar.dateComponents([.day], from: current, to: due).day ?? 0
        if days < 0 {
            return "Overdue · \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "Due \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

@available(iOSApplicationExtension 17.0, *)
private struct AccountBalancesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AccountBalancesEntry

    private var displayedAccounts: [AccountItem] {
        guard let selectedAccountIDs = entry.selectedAccountIDs else {
            return entry.snapshot.accounts
        }
        let selectedIDs = Set(selectedAccountIDs)
        return entry.snapshot.accounts.filter { selectedIDs.contains($0.id) }
    }

    private var rowLimit: Int {
        switch family {
        case .systemSmall: return 2
        case .systemLarge: return 8
        default: return 4
        }
    }

    private var visibleAccounts: [AccountItem] {
        Array(displayedAccounts.prefix(rowLimit))
    }

    private var summary: String {
        if entry.snapshot.hideBalances { return "••••" }
        let currencies = Set(visibleAccounts.map(\.currency))
        if currencies.count > 1 {
            return "\(visibleAccounts.count) accounts"
        }
        let currency = currencies.first ?? entry.snapshot.totalCurrency ?? "USD"
        return money(visibleBalance, currency)
    }

    private var visibleBalance: Double {
        visibleAccounts.reduce(0) { total, account in
            total + balance(for: account)
        }
    }

    private var title: String {
        let plural = displayedAccounts.count != 1
        switch (entry.balanceType, plural) {
        case (.available, true): return "Available Balances"
        case (.available, false): return "Available Balance"
        case (.current, true): return "Current Balances"
        case (.current, false): return "Current Balance"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(
                title: title,
                summary: summary,
                foreground: entry.snapshot.widgetForegroundColor
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(entry.snapshot.widgetColor)

            VStack(alignment: .leading, spacing: 0) {
                if displayedAccounts.isEmpty {
                    Spacer()
                    Text(entry.selectedAccountIDs == nil ? "No active accounts" : "Selected accounts unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    ForEach(Array(visibleAccounts.enumerated()), id: \.element.id) { index, account in
                        Link(destination: accountURL(account)) {
                            HStack(spacing: 6) {
                                Text(account.name).font(.caption.bold()).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(
                                    entry.snapshot.hideBalances
                                        ? "••••"
                                        : money(balance(for: account), account.currency)
                                )
                                .font(.caption)
                                .lineLimit(1)
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(.vertical, 7)
                        if index < visibleAccounts.count - 1 {
                            Divider().overlay(entry.snapshot.widgetColor)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cashSenseWidgetBackground(Color(.systemBackground))
        .widgetURL(URL(string: "cashsense://accounts"))
    }

    private func accountURL(_ account: AccountItem) -> URL {
        var components = URLComponents(string: "cashsense://accounts")!
        components.queryItems = [URLQueryItem(name: "accountId", value: account.id)]
        return components.url!
    }

    private func balance(for account: AccountItem) -> Double {
        switch entry.balanceType {
        case .available:
            return account.balance
        case .current:
            return account.currentBalance ?? account.balance
        }
    }

    private func money(_ amount: Double, _ currency: String) -> String {
        amount.formatted(.currency(code: currency))
    }
}

@available(iOSApplicationExtension 17.0, *)
private struct UpcomingBillsWidget: Widget {
    let kind = "ConfigurableUpcomingBillsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigureUpcomingBillsIntent.self,
            provider: UpcomingBillsProvider()
        ) { entry in
            UpcomingBillsView(entry: entry)
        }
        .configurationDisplayName("Upcoming Bills")
        .description("See upcoming, paid, unpaid, or past-due bills.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@available(iOSApplicationExtension 17.0, *)
private struct AccountBalancesWidget: Widget {
    // This intentionally uses a new kind. Reusing the old StaticConfiguration
    // kind leaves existing iOS widgets cached as non-editable blank instances.
    let kind = "ConfigurableAccountBalancesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectBalanceAccountIntent.self,
            provider: AccountBalancesProvider()
        ) { entry in
            AccountBalancesView(entry: entry)
        }
        .configurationDisplayName("Account Balances")
        .description("See available or current balances for selected accounts.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct CashSenseWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        UpcomingBillsWidget()
        AccountBalancesWidget()
    }
}
