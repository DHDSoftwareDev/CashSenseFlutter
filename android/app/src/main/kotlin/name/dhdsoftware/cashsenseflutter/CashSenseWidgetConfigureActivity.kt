package name.dhdsoftware.cashsenseflutter

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject

class CashSenseWidgetConfigureActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var isBillsWidget = false
    private var billsFilter = "unpaid"
    private var balanceType = "available"
    private var allAccounts = true
    private val selectedAccountIds = mutableSetOf<String>()
    private val accountChecks = mutableListOf<Pair<String, CheckBox>>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)

        appWidgetId = intent
            .getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val manager = AppWidgetManager.getInstance(this)
        val providerName = manager.getAppWidgetInfo(appWidgetId)?.provider?.className.orEmpty()
        isBillsWidget = providerName.endsWith("UpcomingBillsWidgetProvider")
        if (!isBillsWidget && !providerName.endsWith("AccountBalancesWidgetProvider")) {
            finish()
            return
        }

        loadConfiguration()
        setContentView(buildScreen())
    }

    private fun loadConfiguration() {
        val preferences = getSharedPreferences(WIDGET_CONFIG_PREFERENCES, Context.MODE_PRIVATE)
        if (isBillsWidget) {
            billsFilter = preferences.getString(billsFilterKey(appWidgetId), "unpaid") ?: "unpaid"
        } else {
            balanceType = preferences.getString(balanceTypeKey(appWidgetId), "available")
                ?: "available"
            val storedAccounts = preferences.getStringSet(selectedAccountsKey(appWidgetId), null)
            allAccounts = storedAccounts == null
            selectedAccountIds.clear()
            storedAccounts?.let(selectedAccountIds::addAll)
        }
    }

    private fun buildScreen(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(12))
            setOnApplyWindowInsetsListener { view, insets ->
                view.setPadding(
                    dp(20) + insets.systemWindowInsetLeft,
                    dp(20) + insets.systemWindowInsetTop,
                    dp(20) + insets.systemWindowInsetRight,
                    dp(12) + insets.systemWindowInsetBottom,
                )
                insets
            }
        }

        root.addView(TextView(this).apply {
            text = if (isBillsWidget) "Configure Upcoming Bills" else "Configure Account Balances"
            textSize = 22f
            setPadding(0, 0, 0, dp(12))
        })

        val options = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        if (isBillsWidget) {
            buildBillsOptions(options)
        } else {
            buildBalanceOptions(options)
        }

        root.addView(
            ScrollView(this).apply { addView(options) },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        root.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
            setPadding(0, dp(12), 0, 0)
            addView(Button(this@CashSenseWidgetConfigureActivity).apply {
                text = "Cancel"
                setOnClickListener { finish() }
            })
            addView(Button(this@CashSenseWidgetConfigureActivity).apply {
                text = "Save"
                setOnClickListener { saveConfiguration() }
            })
        })

        return root
    }

    private fun buildBillsOptions(container: LinearLayout) {
        container.addView(sectionLabel("Bills to show"))
        val choices = listOf(
            "all" to "Paid and unpaid",
            "unpaid" to "Unpaid only",
            "paid" to "Paid only",
            "pastDue" to "Past due only",
        )
        container.addView(RadioGroup(this).apply {
            orientation = RadioGroup.VERTICAL
            choices.forEach { (value, label) ->
                addView(RadioButton(this@CashSenseWidgetConfigureActivity).apply {
                    id = View.generateViewId()
                    text = label
                    tag = value
                    isChecked = billsFilter == value
                })
            }
            setOnCheckedChangeListener { group, checkedId ->
                billsFilter = group.findViewById<RadioButton>(checkedId).tag.toString()
            }
        })
    }

    private fun buildBalanceOptions(container: LinearLayout) {
        container.addView(sectionLabel("Balance type"))
        container.addView(RadioGroup(this).apply {
            orientation = RadioGroup.VERTICAL
            listOf("available" to "Available balance", "current" to "Current balance")
                .forEach { (value, label) ->
                    addView(RadioButton(this@CashSenseWidgetConfigureActivity).apply {
                        id = View.generateViewId()
                        text = label
                        tag = value
                        isChecked = balanceType == value
                    })
                }
            setOnCheckedChangeListener { group, checkedId ->
                balanceType = group.findViewById<RadioButton>(checkedId).tag.toString()
            }
        })

        container.addView(sectionLabel("Accounts"))
        val allAccountsCheck = CheckBox(this).apply {
            text = "All accounts"
            isChecked = allAccounts
        }
        container.addView(allAccountsCheck)

        val snapshot = getSharedPreferences(HOME_WIDGET_PREFERENCES, Context.MODE_PRIVATE)
            .getString("cashsense_widget_snapshot", null)
            ?.let { runCatching { JSONObject(it) }.getOrNull() }
        val accounts = snapshot?.optJSONArray("accounts")
        if (accounts == null || accounts.length() == 0) {
            container.addView(TextView(this).apply {
                text = "Open CashSense once to load your accounts."
                setPadding(dp(12), dp(8), 0, dp(8))
            })
        } else {
            for (index in 0 until accounts.length()) {
                val account = accounts.optJSONObject(index) ?: continue
                val id = account.optString("id")
                if (id.isEmpty()) continue
                val check = CheckBox(this).apply {
                    text = account.optString("name", "Account")
                    isChecked = selectedAccountIds.contains(id)
                    isEnabled = !allAccounts
                    setPadding(dp(12), 0, 0, 0)
                    setOnCheckedChangeListener { _, checked ->
                        if (checked) selectedAccountIds.add(id) else selectedAccountIds.remove(id)
                    }
                }
                accountChecks.add(id to check)
                container.addView(check)
            }
        }

        allAccountsCheck.setOnCheckedChangeListener { _, checked ->
            allAccounts = checked
            accountChecks.forEach { (_, check) -> check.isEnabled = !checked }
        }
    }

    private fun sectionLabel(label: String) = TextView(this).apply {
        text = label
        textSize = 16f
        setPadding(0, dp(12), 0, dp(4))
    }

    private fun saveConfiguration() {
        if (!isBillsWidget && !allAccounts && selectedAccountIds.isEmpty()) {
            Toast.makeText(this, "Select at least one account", Toast.LENGTH_SHORT).show()
            return
        }

        val editor = getSharedPreferences(WIDGET_CONFIG_PREFERENCES, Context.MODE_PRIVATE).edit()
        if (isBillsWidget) {
            editor.putString(billsFilterKey(appWidgetId), billsFilter)
        } else {
            editor.putString(balanceTypeKey(appWidgetId), balanceType)
            if (allAccounts) {
                editor.remove(selectedAccountsKey(appWidgetId))
            } else {
                editor.putStringSet(selectedAccountsKey(appWidgetId), selectedAccountIds.toSet())
            }
        }
        editor.apply()

        val manager = AppWidgetManager.getInstance(this)
        val widgetData = getSharedPreferences(HOME_WIDGET_PREFERENCES, Context.MODE_PRIVATE)
        if (isBillsWidget) {
            UpcomingBillsWidgetProvider().onUpdate(this, manager, intArrayOf(appWidgetId), widgetData)
        } else {
            AccountBalancesWidgetProvider().onUpdate(this, manager, intArrayOf(appWidgetId), widgetData)
        }

        setResult(
            RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
        )
        finish()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
