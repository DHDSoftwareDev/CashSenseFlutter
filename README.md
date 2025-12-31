# CashSense Flutter

A modern, elegant personal finance tracker built with Flutter. CashSense helps you manage your income, expenses, and financial insights with a clean, intuitive interface.

## Features

### 📱 Core Functionality
- **Transaction Management**: Add, edit, view, and delete income and expense transactions
- **Category System**: Organize transactions with customizable categories (with default categories included)
- **Dashboard Overview**: Quick glance at your financial status with balance, recent transactions, and quick actions
- **Multi-Device Support**: Runs on iOS, Android, Web, macOS, Windows, and Linux

### 📊 Financial Analytics
- **Reports & Charts**: Visual insights with pie charts and trend analysis
- **Period Filtering**: View data by week, month, or year
- **Category Breakdown**: See where your money goes with detailed category analysis
- **Monthly Trends**: Track your income and expense patterns over time

### 🎨 User Experience
- **Material Design 3**: Modern, clean interface following Google's latest design guidelines
- **Custom Theme**: Professional green color scheme optimized for financial apps
- **Responsive Design**: Works seamlessly across different screen sizes
- **Offline First**: All data stored locally with Hive database

### 🛠 Technical Features
- **Local Storage**: Your data stays on your device using Hive database
- **No Cloud Dependencies**: Complete privacy with local-only data storage
- **Fast Performance**: Optimized for smooth user experience
- **Cross-Platform**: Single codebase for all platforms

## Screenshots

The app includes:
- **Dashboard**: Overview of your financial status
- **Transactions**: Detailed transaction history with filtering
- **Categories**: Manage your expense and income categories
- **Reports**: Visual analytics with charts and insights
- **Settings**: App preferences and data management

## Getting Started

### Prerequisites
- Flutter SDK (3.9.2 or later)
- Dart SDK
- Platform-specific requirements for your target devices

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd cashsenseflutter
```

2. Install dependencies:
```bash
flutter pub get
```

3. Generate Hive type adapters:
```bash
flutter packages pub run build_runner build
```

4. Run the app:
```bash
# For web
flutter run -d chrome

# For iOS
flutter run -d ios

# For Android
flutter run -d android

# For desktop
flutter run -d macos  # or windows/linux
```

## Architecture

### Project Structure
```
lib/
├── main.dart                    # App entry point
├── models/                      # Data models
│   ├── transaction.dart         # Transaction model with Hive annotations
│   ├── category.dart           # Category model with default categories
│   └── account.dart            # Account model for future use
├── services/                    # Business logic
│   └── database_service.dart   # Hive database operations
├── screens/                     # UI screens
│   ├── main_navigation_screen.dart
│   ├── dashboard_screen.dart
│   ├── transactions_screen.dart
│   ├── add_transaction_screen.dart
│   ├── categories_screen.dart
│   ├── reports_screen.dart
│   └── settings_screen.dart
└── theme/                      # App theming
    └── app_theme.dart          # Custom theme and colors
```

### Dependencies
- **hive & hive_flutter**: Local database storage
- **fl_chart**: Beautiful charts and graphs
- **intl**: Internationalization and formatting
- **provider**: State management (ready for future use)
- **material_design_icons_flutter**: Additional icon options

## Data Models

### Transaction
- ID, amount, category, type (income/expense)
- Description, date, optional notes
- Full CRUD operations supported

### Category
- Customizable categories with icons and colors
- Default categories for common expenses and income types
- Budget limit support (foundation for future budgeting features)

### Account
- Multi-account support ready (currently single account)
- Different account types (cash, bank, card, investment)

## Features in Detail

### Dashboard
- Total balance display with gradient card
- Monthly income and expense overview
- Quick action buttons for adding transactions
- Recent transactions list with category icons

### Transaction Management
- Comprehensive transaction form with validation
- Category selection with visual icons
- Date picker for flexible transaction dating
- Transaction history with grouping by date
- Delete functionality with confirmation

### Reports & Analytics
- Period-based filtering (week, month, year)
- Pie chart for expense categorization
- Line chart for 6-month trends
- Summary cards for key financial metrics

### Categories
- Pre-loaded default categories for immediate use
- Category details with transaction counts
- Icon and color coding for easy identification

### Settings
- Data management (clear all data)
- About information and privacy policy
- Future-ready for additional preferences

## Privacy & Security

- **Local Data Only**: All financial data is stored locally on your device
- **No Cloud Services**: No data transmission to external servers
- **No Analytics**: No tracking or data collection
- **Open Source**: Transparent codebase

## Future Enhancements

The app is designed with extensibility in mind:

- [ ] **Budgeting**: Set and track category budgets
- [ ] **Multi-Currency**: Support for different currencies
- [ ] **Data Export**: CSV/PDF export capabilities
- [ ] **Backup/Restore**: Cloud backup options
- [ ] **Recurring Transactions**: Automatic transaction creation
- [ ] **Search & Filters**: Advanced transaction filtering
- [ ] **Account Management**: Multiple account support
- [ ] **Bill Reminders**: Payment due date notifications

## Contributing

This project is open for contributions! Areas where help is welcome:

1. **UI/UX Improvements**: Better animations, transitions
2. **New Features**: Implement the future enhancements listed above
3. **Platform Optimization**: iOS/Android specific improvements
4. **Testing**: Unit tests and integration tests
5. **Documentation**: Improve documentation and add tutorials

## Technical Notes

### Database
- Uses Hive for fast, local NoSQL storage
- Type adapters generated for all models
- Automatic initialization with default data

### State Management
- Currently uses StatefulWidget for simplicity
- Provider package included for future state management needs
- Ready for migration to more complex state management if needed

### Performance
- Optimized list rendering with proper keys
- Efficient database queries with indexed lookups
- Memory-conscious chart rendering

## License

This project is available for personal and educational use. Please check the license file for detailed terms.

## Support

For questions, issues, or contributions:
1. Check existing issues in the repository
2. Create new issues with detailed descriptions
3. Follow the contribution guidelines

---

**CashSense** - Take control of your finances with style and privacy. 💰📊✨
