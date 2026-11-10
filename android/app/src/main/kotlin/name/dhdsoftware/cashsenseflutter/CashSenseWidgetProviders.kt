package name.dhdsoftware.cashsenseflutter

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.DateFormat
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Currency
import java.util.Date
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

private const val SNAPSHOT_KEY = "cashsense_widget_snapshot"
internal const val HOME_WIDGET_PREFERENCES = "HomeWidgetPreferences"
internal const val WIDGET_CONFIG_PREFERENCES = "CashSenseWidgetConfiguration"

internal fun billsFilterKey(widgetId: Int) = "bills_filter_$widgetId"
internal fun balanceTypeKey(widgetId: Int) = "balance_type_$widgetId"
internal fun selectedAccountsKey(widgetId: Int) = "selected_accounts_$widgetId"

private fun clearWidgetConfiguration(context: Context, widgetIds: IntArray) {
    val editor = context
        .getSharedPreferences(WIDGET_CONFIG_PREFERENCES, Context.MODE_PRIVATE)
        .edit()
    widgetIds.forEach { widgetId ->
        editor.remove(billsFilterKey(widgetId))
        editor.remove(balanceTypeKey(widgetId))
        editor.remove(selectedAccountsKey(widgetId))
    }
    editor.apply()
}

private val rowIds = intArrayOf(
    R.id.widget_row_1,
    R.id.widget_row_2,
    R.id.widget_row_3,
    R.id.widget_row_4,
    R.id.widget_row_5,
    R.id.widget_row_6,
    R.id.widget_row_7,
    R.id.widget_row_8,
)
private val rowNameIds = intArrayOf(
    R.id.widget_row_1_name,
    R.id.widget_row_2_name,
    R.id.widget_row_3_name,
    R.id.widget_row_4_name,
    R.id.widget_row_5_name,
    R.id.widget_row_6_name,
    R.id.widget_row_7_name,
    R.id.widget_row_8_name,
)
private val rowIconIds = intArrayOf(
    R.id.widget_row_1_icon,
    R.id.widget_row_2_icon,
    R.id.widget_row_3_icon,
    R.id.widget_row_4_icon,
    R.id.widget_row_5_icon,
    R.id.widget_row_6_icon,
    R.id.widget_row_7_icon,
    R.id.widget_row_8_icon,
)
private val rowValueIds = intArrayOf(
    R.id.widget_row_1_value,
    R.id.widget_row_2_value,
    R.id.widget_row_3_value,
    R.id.widget_row_4_value,
    R.id.widget_row_5_value,
    R.id.widget_row_6_value,
    R.id.widget_row_7_value,
    R.id.widget_row_8_value,
)
private val rowDividerIds = intArrayOf(
    R.id.widget_row_divider_1,
    R.id.widget_row_divider_2,
    R.id.widget_row_divider_3,
    R.id.widget_row_divider_4,
    R.id.widget_row_divider_5,
    R.id.widget_row_divider_6,
    R.id.widget_row_divider_7,
)

private fun snapshot(widgetData: SharedPreferences): JSONObject? =
    widgetData.getString(SNAPSHOT_KEY, null)?.let { raw ->
        runCatching { JSONObject(raw) }.getOrNull()
    }

private fun widgetViews(context: Context): RemoteViews =
    RemoteViews(context.packageName, R.layout.cashsense_summary_widget)

private fun widgetThemeColor(data: JSONObject?): Int {
    val rgb = (data?.optLong("primaryColor", 0xFF2E7D32L) ?: 0xFF2E7D32L).toInt()
    return rgb or Color.BLACK
}

private fun readableForeground(background: Int): Int {
    fun linear(channel: Int): Double {
        val value = channel / 255.0
        return if (value <= 0.04045) value / 12.92 else Math.pow((value + 0.055) / 1.055, 2.4)
    }
    val luminance =
        0.2126 * linear(Color.red(background)) +
            0.7152 * linear(Color.green(background)) +
            0.0722 * linear(Color.blue(background))
    return if (luminance > 0.42) Color.BLACK else Color.WHITE
}

private fun RemoteViews.applyTheme(data: JSONObject?) {
    val accent = widgetThemeColor(data)
    val headerForeground = readableForeground(accent)
    setInt(R.id.widget_header, "setBackgroundColor", accent)
    setTextColor(R.id.widget_title, headerForeground)
    setTextColor(
        R.id.widget_summary,
        Color.argb(
            194,
            Color.red(headerForeground),
            Color.green(headerForeground),
            Color.blue(headerForeground),
        ),
    )
    setInt(R.id.widget_icon, "setColorFilter", headerForeground)
    setTextColor(R.id.widget_empty, Color.DKGRAY)
    setInt(R.id.widget_divider, "setBackgroundColor", accent)
    rowNameIds.forEach { setTextColor(it, Color.rgb(33, 33, 33)) }
    rowValueIds.forEach { setTextColor(it, Color.rgb(33, 33, 33)) }
    rowDividerIds.forEach { setInt(it, "setBackgroundColor", accent) }
}

private fun RemoteViews.resetRows(emptyMessage: String) {
    setTextViewText(R.id.widget_empty, emptyMessage)
    setViewVisibility(R.id.widget_empty, View.VISIBLE)
    rowIds.forEach { setViewVisibility(it, View.GONE) }
    rowDividerIds.forEach { setViewVisibility(it, View.GONE) }
}

private fun RemoteViews.showRow(
    index: Int,
    name: String,
    value: String,
    context: Context,
    uri: Uri,
    iconResource: Int,
    iconTint: Int,
    showDivider: Boolean = false,
) {
    if (index !in rowIds.indices) return
    setViewVisibility(R.id.widget_empty, View.GONE)
    setViewVisibility(rowIds[index], View.VISIBLE)
    if (showDivider && index > 0) {
        setViewVisibility(rowDividerIds[index - 1], View.VISIBLE)
    }
    setImageViewResource(rowIconIds[index], iconResource)
    setInt(rowIconIds[index], "setColorFilter", iconTint)
    setTextViewText(rowNameIds[index], name)
    setTextViewText(rowValueIds[index], value)
    setOnClickPendingIntent(
        rowIds[index],
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri),
    )
}

private fun visibleRowLimit(
    appWidgetManager: AppWidgetManager,
    widgetId: Int,
): Int {
    val minHeight = appWidgetManager
        .getAppWidgetOptions(widgetId)
        .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
    val rowsThatFit = when {
        minHeight >= 360 -> 8
        minHeight >= 320 -> 7
        minHeight >= 280 -> 6
        minHeight >= 240 -> 5
        minHeight >= 170 -> 4
        minHeight >= 140 -> 3
        else -> 2
    }
    return minOf(rowsThatFit, rowIds.size)
}

private fun currency(amount: Double, currencyCode: String = "USD"): String {
    val formatter = NumberFormat.getCurrencyInstance()
    runCatching { formatter.currency = Currency.getInstance(currencyCode) }
    return formatter.format(amount)
}

private fun dueLabel(dueMillis: Long): String {
    val due = Calendar.getInstance().apply { timeInMillis = dueMillis }
    val today = Calendar.getInstance()
    fun sameDay(a: Calendar, b: Calendar): Boolean =
        a.get(Calendar.ERA) == b.get(Calendar.ERA) &&
            a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
            a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
    if (sameDay(due, today)) return "Today"
    val tomorrow = (today.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
    if (sameDay(due, tomorrow)) return "Tomorrow"
    return DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(dueMillis))
}

class UpcomingBillsWidgetProvider : HomeWidgetProvider() {
    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        val manager = AppWidgetManager.getInstance(context)
        val widgetIds = manager.getAppWidgetIds(ComponentName(context, javaClass))
        if (widgetIds.isNotEmpty()) {
            onUpdate(
                context,
                manager,
                widgetIds,
                context.getSharedPreferences(HOME_WIDGET_PREFERENCES, Context.MODE_PRIVATE),
            )
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        clearWidgetConfiguration(context, appWidgetIds)
        super.onDeleted(context, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        onUpdate(
            context,
            appWidgetManager,
            intArrayOf(appWidgetId),
            context.getSharedPreferences(HOME_WIDGET_PREFERENCES, Context.MODE_PRIVATE),
        )
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val data = snapshot(widgetData)
        val storedBills = data?.optJSONArray("bills") ?: JSONArray()
        val today = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startOfToday = today.timeInMillis
        val allBills = (0 until storedBills.length()).mapNotNull { index ->
            storedBills.optJSONObject(index)
        }.sortedBy { bill -> bill.optLong("dueMillis") }
        val config = context.getSharedPreferences(WIDGET_CONFIG_PREFERENCES, Context.MODE_PRIVATE)
        appWidgetIds.forEach { widgetId ->
            val filter = config.getString(billsFilterKey(widgetId), "unpaid") ?: "unpaid"
            val bills = allBills.filter { bill ->
                val isPastDue = bill.optLong("dueMillis") < startOfToday
                val isPaid = bill.optString("paymentStatus") == "paid"
                when (filter) {
                    "all" -> !isPastDue
                    "paid" -> !isPastDue && isPaid
                    "pastDue" -> isPastDue && !isPaid
                    else -> !isPastDue && !isPaid
                }
            }
            val emptyMessage = when (filter) {
                "all" -> "No upcoming bills"
                "paid" -> "No upcoming paid bills"
                "pastDue" -> "No past-due bills"
                else -> "No upcoming unpaid bills"
            }
            val maxRows = visibleRowLimit(appWidgetManager, widgetId)
            val views = widgetViews(context)
            views.applyTheme(data)
            views.setImageViewResource(
                R.id.widget_icon,
                R.drawable.ic_widget_upcoming_bills,
            )
            views.setTextViewText(R.id.widget_title, "Upcoming Bills")
            val billsDueThisMonth = bills.count { bill ->
                val due = Calendar.getInstance().apply {
                    timeInMillis = bill.optLong("dueMillis")
                }
                due.get(Calendar.YEAR) == today.get(Calendar.YEAR) &&
                    due.get(Calendar.MONTH) == today.get(Calendar.MONTH)
            }
            val month = SimpleDateFormat("MMM", Locale.getDefault()).format(today.time)
            views.setTextViewText(
                R.id.widget_summary,
                if (filter == "pastDue") {
                    "${bills.size} past due"
                } else {
                    "$month · $billsDueThisMonth due"
                },
            )
            views.resetRows(emptyMessage)
            for (index in 0 until minOf(bills.size, maxRows)) {
                val bill = bills[index]
                val isPaid = bill.optString("paymentStatus") == "paid"
                val dueMillis = bill.optLong("dueMillis")
                val amount = currency(bill.optDouble("amount"))
                val note = bill.optString("note").trim()
                val name = bill.optString("name", "Bill")
                val nameWithNote = if (note.isEmpty()) name else "$name\n$note"
                val paidPrefix = if (isPaid) "Paid · " else ""
                views.showRow(
                    index,
                    nameWithNote,
                    "$paidPrefix${dueLabel(dueMillis)} · $amount",
                    context,
                    Uri.parse("cashsense://bills?date=$dueMillis"),
                    if (isPaid) R.drawable.ic_widget_row_check else R.drawable.ic_widget_row_bill,
                    if (isPaid) Color.rgb(46, 125, 50) else widgetThemeColor(data),
                    showDivider = true,
                )
            }
            views.setOnClickPendingIntent(
                R.id.widget_container,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("cashsense://bills"),
                ),
            )
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}

class AccountBalancesWidgetProvider : HomeWidgetProvider() {
    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        val manager = AppWidgetManager.getInstance(context)
        val widgetIds = manager.getAppWidgetIds(ComponentName(context, javaClass))
        if (widgetIds.isNotEmpty()) {
            onUpdate(
                context,
                manager,
                widgetIds,
                context.getSharedPreferences(HOME_WIDGET_PREFERENCES, Context.MODE_PRIVATE),
            )
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        clearWidgetConfiguration(context, appWidgetIds)
        super.onDeleted(context, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        onUpdate(
            context,
            appWidgetManager,
            intArrayOf(appWidgetId),
            context.getSharedPreferences(HOME_WIDGET_PREFERENCES, Context.MODE_PRIVATE),
        )
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val data = snapshot(widgetData)
        val accounts = data?.optJSONArray("accounts") ?: JSONArray()
        val hidden = data?.optBoolean("hideBalances", false) ?: false
        val config = context.getSharedPreferences(WIDGET_CONFIG_PREFERENCES, Context.MODE_PRIVATE)
        appWidgetIds.forEach { widgetId ->
            val selectedIds = config.getStringSet(selectedAccountsKey(widgetId), null)
            val balanceType = config.getString(balanceTypeKey(widgetId), "available")
                ?: "available"
            val maxRows = visibleRowLimit(appWidgetManager, widgetId)
            val views = widgetViews(context)
            views.applyTheme(data)
            views.setImageViewResource(
                R.id.widget_icon,
                R.drawable.ic_widget_account_balances,
            )
            val configuredAccounts = (0 until accounts.length()).mapNotNull { index ->
                accounts.optJSONObject(index)
            }.filter { account ->
                selectedIds == null || selectedIds.contains(account.optString("id"))
            }
            val plural = configuredAccounts.size != 1
            views.setTextViewText(
                R.id.widget_title,
                when {
                    balanceType == "current" && plural -> "Current Balances"
                    balanceType == "current" -> "Current Balance"
                    plural -> "Available Balances"
                    else -> "Available Balance"
                },
            )
            val visibleAccounts = configuredAccounts.take(maxRows)
            val visibleCurrencies = visibleAccounts.map { account ->
                account.optString("currency", "USD")
            }.toSet()
            val totalSummary = when {
                hidden -> "••••"
                visibleCurrencies.size > 1 ->
                    if (visibleAccounts.size == 1) "1 account" else "${visibleAccounts.size} accounts"
                else -> currency(
                    visibleAccounts.sumOf { account ->
                        if (balanceType == "current") {
                            account.optDouble("currentBalance", account.optDouble("balance"))
                        } else {
                            account.optDouble("balance")
                        }
                    },
                    visibleCurrencies.firstOrNull()
                        ?: data?.optString("totalCurrency", "USD")
                        ?: "USD",
                )
            }
            views.setTextViewText(R.id.widget_summary, totalSummary)
            views.resetRows(
                if (selectedIds == null) "No active accounts" else "Selected accounts unavailable",
            )
            for ((index, account) in visibleAccounts.withIndex()) {
                val value = if (hidden) {
                    "••••"
                } else {
                    currency(
                        if (balanceType == "current") {
                            account.optDouble("currentBalance", account.optDouble("balance"))
                        } else {
                            account.optDouble("balance")
                        },
                        account.optString("currency", "USD"),
                    )
                }
                views.showRow(
                    index,
                    account.optString("name", "Account"),
                    value,
                    context,
                    Uri.parse(
                        "cashsense://accounts?accountId=${Uri.encode(account.optString("id"))}",
                    ),
                    R.drawable.ic_widget_row_account,
                    widgetThemeColor(data),
                    showDivider = true,
                )
            }
            views.setOnClickPendingIntent(
                R.id.widget_container,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("cashsense://accounts"),
                ),
            )
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
