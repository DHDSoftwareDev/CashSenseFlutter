package name.dhdsoftware.cashsenseflutter

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.DateFormat
import java.text.NumberFormat
import java.util.Calendar
import java.util.Currency
import java.util.Date
import org.json.JSONArray
import org.json.JSONObject

private const val SNAPSHOT_KEY = "cashsense_widget_snapshot"

private val rowIds = intArrayOf(
    R.id.widget_row_1,
    R.id.widget_row_2,
    R.id.widget_row_3,
    R.id.widget_row_4,
)
private val rowNameIds = intArrayOf(
    R.id.widget_row_1_name,
    R.id.widget_row_2_name,
    R.id.widget_row_3_name,
    R.id.widget_row_4_name,
)
private val rowValueIds = intArrayOf(
    R.id.widget_row_1_value,
    R.id.widget_row_2_value,
    R.id.widget_row_3_value,
    R.id.widget_row_4_value,
)
private val rowDividerIds = intArrayOf(
    R.id.widget_row_divider_1,
    R.id.widget_row_divider_2,
    R.id.widget_row_divider_3,
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
    setTextColor(R.id.widget_summary, headerForeground)
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
    showDivider: Boolean = false,
) {
    if (index !in rowIds.indices) return
    setViewVisibility(R.id.widget_empty, View.GONE)
    setViewVisibility(rowIds[index], View.VISIBLE)
    if (showDivider && index > 0) {
        setViewVisibility(rowDividerIds[index - 1], View.VISIBLE)
    }
    setTextViewText(rowNameIds[index], name)
    setTextViewText(rowValueIds[index], value)
    setOnClickPendingIntent(
        rowIds[index],
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri),
    )
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
        val oneMonthFromToday = (today.clone() as Calendar).apply {
            add(Calendar.MONTH, 1)
        }.timeInMillis
        val bills = (0 until storedBills.length()).mapNotNull { index ->
            storedBills.optJSONObject(index)
        }.filter { bill ->
            val dueMillis = bill.optLong("dueMillis")
            dueMillis >= startOfToday &&
                dueMillis <= oneMonthFromToday &&
                bill.optString("paymentStatus") != "paid"
        }
        appWidgetIds.forEach { widgetId ->
            val views = widgetViews(context)
            views.applyTheme(data)
            views.setTextViewText(R.id.widget_title, "Upcoming Bills")
            views.setTextViewText(
                R.id.widget_summary,
                if (bills.size == 1) "1 due" else "${bills.size} due",
            )
            views.resetRows("No upcoming unpaid bills")
            for (index in 0 until minOf(bills.size, rowIds.size)) {
                val bill = bills[index]
                val dueMillis = bill.optLong("dueMillis")
                val amount = currency(bill.optDouble("amount"))
                views.showRow(
                    index,
                    bill.optString("name", "Bill"),
                    "${dueLabel(dueMillis)} · $amount",
                    context,
                    Uri.parse("cashsense://bills?date=$dueMillis"),
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
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val data = snapshot(widgetData)
        val accounts = data?.optJSONArray("accounts") ?: JSONArray()
        val hidden = data?.optBoolean("hideBalances", false) ?: false
        appWidgetIds.forEach { widgetId ->
            val views = widgetViews(context)
            views.applyTheme(data)
            views.setTextViewText(R.id.widget_title, "Available Balances")
            val mixedCurrencies = data?.optBoolean("hasMixedCurrencies", false) ?: false
            val totalSummary = when {
                hidden -> "••••"
                mixedCurrencies -> if (accounts.length() == 1) "1 account" else "${accounts.length()} accounts"
                else -> currency(
                    data?.optDouble("totalAvailable") ?: 0.0,
                    data?.optString("totalCurrency", "USD") ?: "USD",
                )
            }
            views.setTextViewText(R.id.widget_summary, totalSummary)
            views.resetRows("No active accounts")
            for (index in 0 until minOf(accounts.length(), rowIds.size)) {
                val account = accounts.optJSONObject(index) ?: continue
                val value = if (hidden) {
                    "••••"
                } else {
                    currency(
                        account.optDouble("balance"),
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
