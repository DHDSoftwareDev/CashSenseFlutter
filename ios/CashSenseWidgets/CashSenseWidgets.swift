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
    let icon: String
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .fill(foreground.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(foreground)
            }
            .frame(width: compact ? 27 : 32, height: compact ? 27 : 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: compact ? 14 : 16, weight: .bold, design: .rounded))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: compact ? 9 : 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(foreground.opacity(0.76))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            Spacer(minLength: 3)
        }
        .fixedSize(horizontal: false, vertical: true)
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
        return visibleBills.filter {
            calendar.isDate($0.dueDate, equalTo: entry.date, toGranularity: .month)
        }.count
    }

    private var billSummary: String {
        if entry.billFilter == .pastDue {
            return "\(visibleBills.count) past due"
        }
        let month = entry.date.formatted(.dateTime.month(.abbreviated))
        return "\(month) · \(billsDueThisMonth) due"
    }

    private var emptyMessage: String {
        switch entry.billFilter {
        case .all: return "No upcoming bills"
        case .unpaid: return "No unpaid bills"
        case .paid: return "No paid bills"
        case .pastDue: return "No past-due bills"
        }
    }

    private var rowLimit: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 2
        case .systemLarge: return 5
        default: return 2
        }
    }

    private var displayedBills: [BillItem] {
        Array(visibleBills.prefix(rowLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if visibleBills.isEmpty {
                emptyState
            } else {
                billsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cashSenseWidgetBackground(Color(.systemBackground))
        .widgetURL(visibleBills.first.map(billURL) ?? URL(string: "cashsense://bills")!)
    }

    private var header: some View {
        WidgetHeader(
            title: family == .systemSmall ? "Bills" : "Upcoming Bills",
            summary: billSummary,
            foreground: entry.snapshot.widgetForegroundColor,
            icon: "calendar.badge.clock",
            compact: family == .systemSmall
        )
        .padding(.horizontal, family == .systemSmall ? 11 : 14)
        .padding(
            .vertical,
            family == .systemSmall ? 7 : (family == .systemMedium ? 8 : 10)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(entry.snapshot.widgetColor)
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: family == .systemSmall ? 23 : 28))
                .foregroundStyle(entry.snapshot.widgetColor.opacity(0.85))
            Text(emptyMessage)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
    }

    private var billsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(displayedBills.enumerated()), id: \.element.id) { index, bill in
                Link(destination: billURL(bill)) {
                    billRow(bill)
                }
                .buttonStyle(.plain)

                if index < displayedBills.count - 1 {
                    Divider()
                        .padding(.leading, family == .systemSmall ? 10 : 38)
                }
            }

            if visibleBills.count > displayedBills.count && family != .systemSmall {
                HStack {
                    Spacer()
                    Text("+\(visibleBills.count - displayedBills.count) more")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(entry.snapshot.widgetColor)
                }
                .padding(.top, family == .systemMedium ? 2 : 4)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, family == .systemSmall ? 9 : 11)
        .padding(.top, family == .systemSmall ? 3 : (family == .systemMedium ? 3 : 6))
        .padding(.bottom, family == .systemMedium ? 3 : 6)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    @ViewBuilder
    private func billRow(_ bill: BillItem) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(bill.name)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 3)
                    Text(bill.amount, format: .currency(code: "USD"))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                HStack(spacing: 4) {
                    Text(dueText(bill.dueDate))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(dueColor(bill))
                        .lineLimit(1)
                    Spacer(minLength: 3)
                    if bill.isPaid {
                        Text("PAID")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.vertical, 6)
            .foregroundStyle(.primary)
        } else {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(entry.snapshot.widgetColor.opacity(0.12))
                    Image(systemName: bill.isPaid ? "checkmark" : "dollarsign")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(bill.isPaid ? .green : entry.snapshot.widgetColor)
                }
                .frame(width: 27, height: 27)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bill.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    if let note = bill.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 5)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(bill.amount, format: .currency(code: "USD"))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(bill.isPaid ? "Paid · \(dueText(bill.dueDate))" : dueText(bill.dueDate))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(dueColor(bill))
                        .lineLimit(1)
                }
            }
            .padding(
                .vertical,
                family == .systemMedium ? 4 : (family == .systemLarge ? 6 : 5)
            )
            .foregroundStyle(.primary)
        }
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

    private func dueColor(_ bill: BillItem) -> Color {
        if bill.isPaid { return .green }
        let calendar = Calendar.autoupdatingCurrent
        let due = calendar.startOfDay(for: bill.dueDate)
        let current = calendar.startOfDay(for: entry.date)
        return due < current ? .red : .secondary
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
        case .systemSmall: return 3
        case .systemLarge: return 8
        default: return 4
        }
    }

    private var visibleAccounts: [AccountItem] {
        Array(displayedAccounts.prefix(rowLimit))
    }

    private var summary: String {
        if entry.snapshot.hideBalances { return "••••" }
        let currencies = Set(displayedAccounts.map(\.currency))
        if currencies.count > 1 {
            return "\(displayedAccounts.count) accounts"
        }
        let currency = currencies.first ?? entry.snapshot.totalCurrency ?? "USD"
        return money(selectedTotal, currency)
    }

    private var selectedTotal: Double {
        displayedAccounts.reduce(0) { $0 + balance(for: $1) }
    }

    private var title: String {
        switch entry.balanceType {
        case .available: return family == .systemSmall ? "Available" : "Available Balance"
        case .current: return family == .systemSmall ? "Current" : "Current Balance"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if displayedAccounts.isEmpty {
                emptyState
            } else {
                accountList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cashSenseWidgetBackground(Color(.systemBackground))
        .widgetURL(URL(string: "cashsense://accounts"))
    }

    private var header: some View {
        WidgetHeader(
            title: title,
            summary: summary,
            foreground: entry.snapshot.widgetForegroundColor,
            icon: "wallet.bifold.fill",
            compact: family == .systemSmall
        )
        .padding(.horizontal, family == .systemSmall ? 10 : 14)
        .padding(.vertical, family == .systemSmall ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(entry.snapshot.widgetColor)
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Spacer(minLength: 0)
            Image(systemName: "wallet.bifold")
                .font(.system(size: family == .systemSmall ? 23 : 28))
                .foregroundStyle(entry.snapshot.widgetColor.opacity(0.8))
            Text(entry.selectedAccountIDs == nil ? "No active accounts" : "Accounts unavailable")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleAccounts.enumerated()), id: \.element.id) { index, account in
                Link(destination: accountURL(account)) {
                    accountRow(account)
                }
                .buttonStyle(.plain)

                if index < visibleAccounts.count - 1 {
                    Divider()
                        .padding(.leading, family == .systemSmall ? 8 : 38)
                }
            }

            if displayedAccounts.count > visibleAccounts.count && family != .systemSmall {
                HStack {
                    Spacer()
                    Text("+\(displayedAccounts.count - visibleAccounts.count) more")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(entry.snapshot.widgetColor)
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, family == .systemSmall ? 9 : 11)
        .padding(.top, family == .systemSmall ? 4 : 6)
        .padding(.bottom, 6)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    @ViewBuilder
    private func accountRow(_ account: AccountItem) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text(
                    entry.snapshot.hideBalances
                        ? "••••"
                        : money(balance(for: account), account.currency)
                )
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(balanceColor(account))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
        } else {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(entry.snapshot.widgetColor.opacity(0.12))
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(entry.snapshot.widgetColor)
                }
                .frame(width: 27, height: 27)

                Text(account.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Spacer(minLength: 5)

                Text(
                    entry.snapshot.hideBalances
                        ? "••••"
                        : money(balance(for: account), account.currency)
                )
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(balanceColor(account))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .padding(.vertical, family == .systemLarge ? 7 : 6)
        }
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

    private func balanceColor(_ account: AccountItem) -> Color {
        if entry.snapshot.hideBalances { return .primary }
        return balance(for: account) < 0 ? .red : .primary
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
