# AWS Sync Integration - Hybrid Storage Architecture

## Overview
Your CashSense app now supports **optional cloud sync with AWS** while maintaining full **offline functionality** with local Hive storage.

## Architecture

### Local Storage (Primary)
- **Technology**: Hive (local NoSQL database)
- **Location**: Device only
- **Always works**: ✅ Offline-first
- **Fast**: ✅ No network latency
- **Primary data source**: All operations read/write to Hive first

### Cloud Sync (Optional)
- **Technology**: AWS backend via REST API
- **Purpose**: Backup and cross-device sync
- **Optional**: Users can enable/disable
- **When**: Syncs hourly when app is open and online
- **Bidirectional**: Pushes local changes, pulls remote changes

## Services Added

### 1. UserAuthService (`lib/services/user_auth_service.dart`)
Manages user authentication state using SharedPreferences:
- `saveUserInfo()` - Save user credentials after login
- `getCurrentUserId()` - Get logged-in user ID
- `isLoggedIn()` - Check if user is logged in
- `logout()` - Clear user data

### 2. SyncService (`lib/services/sync_service.dart`)
Handles bidirectional sync between local Hive and AWS:
- `enableSync()` - Enable cloud sync for a user
- `performFullSync()` - Manually trigger full sync
- `autoSync()` - Automatic sync (runs hourly)
- `disableSync()` - Disable sync and clear credentials

**Sync Order:**
1. Categories → 2. Accounts → 3. Transactions → 4. Bills

### 3. SyncSettingsScreen (`lib/screens/sync_settings_screen.dart`)
User interface for managing sync:
- Enable/disable cloud sync
- Manual sync button
- Sync status display
- Last sync time
- User email display

## How It Works

### On App Startup
```dart
// main.dart
await DatabaseService.init();  // Initialize local Hive storage
await SyncService().autoSync(); // Auto-sync if logged in (doesn't block)
```

### User Flow

#### Enabling Sync
1. User opens Sync Settings screen
2. Toggles "Enable Sync"
3. Enters User ID and Email
4. App performs initial full sync
5. Saves user credentials locally

#### Ongoing Sync
- Automatic sync every hour when app is open
- Manual sync via "Sync Now" button
- All operations work offline immediately
- Sync happens in background when online

#### Disabling Sync
1. User toggles "Disable Sync"
2. Confirms action
3. Local data remains intact
4. Credentials cleared
5. No more syncing

### Data Flow

```
User Action (Add Transaction)
        ↓
   Save to Hive (immediate)
        ↓
   Display updated (fast)
        ↓
[Next sync cycle]
        ↓
   Push to AWS (background)
```

## Adding Sync to Settings

To add the Sync Settings screen to your settings menu:

```dart
// In your settings screen, add:
ListTile(
  leading: const Icon(Icons.cloud_sync),
  title: const Text('Cloud Sync'),
  subtitle: const Text('Backup & sync your data'),
  trailing: const Icon(Icons.arrow_forward_ios),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SyncSettingsScreen(),
      ),
    );
  },
),
```

## Benefits

### For Users
- ✅ App works fully offline
- ✅ Optional cloud backup
- ✅ Cross-device sync capability
- ✅ Fast performance (local-first)
- ✅ No forced registration

### For Development
- ✅ No breaking changes to existing code
- ✅ DatabaseService remains unchanged
- ✅ Easy to test (sync is optional)
- ✅ Can add features gradually
- ✅ Rollback-friendly

## AWS Backend Requirements

Your AWS backend should support these endpoints:

### User Endpoints
- `POST /api/users` - Create user
- `GET /api/users/:userId` - Get user

### Transaction Endpoints
- `GET /api/users/:userId/transactions` - List transactions
- `POST /api/users/:userId/transactions` - Create transaction
- `DELETE /api/users/:userId/transactions/:transactionId` - Delete

### Category Endpoints
- `GET /api/users/:userId/categories` - List categories
- `POST /api/users/:userId/categories` - Create category

### Account Endpoints
- `GET /api/users/:userId/accounts` - List accounts
- `POST /api/users/:userId/accounts` - Create account

### Bill Endpoints
- `GET /api/users/:userId/bills` - List bills
- `POST /api/users/:userId/bills` - Create bill

### Health Check
- `GET /api/health` - Health check endpoint

## Configuration

Update AWS backend URL in `lib/services/aws_service.dart`:

```dart
static const String baseUrl = 'https://your-backend-url.com/api';
```

## Testing

### Test Offline Mode
1. Disable WiFi/Cellular
2. Use app normally
3. All features should work

### Test Sync
1. Enable sync in settings
2. Add transaction on Device A
3. Wait for sync or trigger manually
4. Check data appears on Device B after sync

### Test Error Handling
1. Enable sync
2. Turn off AWS backend
3. App should continue working locally
4. Sync will retry automatically

## Next Steps

1. **Deploy AWS Backend** - Set up your backend infrastructure
2. **Update baseUrl** - Point to your AWS API Gateway
3. **Test Sync** - Verify bidirectional sync works
4. **Add to Settings** - Integrate SyncSettingsScreen into app
5. **Monitor** - Watch sync logs for issues

## Troubleshooting

### Sync Not Working
- Check AWS backend is running (`checkHealth()`)
- Verify user is logged in (`isLoggedIn()`)
- Check network connectivity
- Look for errors in `syncError.value`

### Data Not Syncing
- Check last sync time
- Manually trigger sync
- Verify AWS endpoints are correct
- Check console logs for errors

### Duplicate Data
- Sync uses IDs to match records
- Duplicates shouldn't occur
- If they do, check ID generation

## Files Modified/Created

### Created
- ✅ `lib/services/user_auth_service.dart` - User authentication
- ✅ `lib/services/sync_service.dart` - Sync logic
- ✅ `lib/screens/sync_settings_screen.dart` - Sync UI

### Modified
- ✅ `lib/main.dart` - Added auto-sync on startup
- ✅ `pubspec.yaml` - Added shared_preferences package

### Existing (Unchanged)
- ✅ `lib/services/database_service.dart` - Still works as before
- ✅ `lib/services/aws_service.dart` - Already had AWS methods
- ✅ All screens - No changes needed

## Summary

You now have a **hybrid storage architecture** that:
- Works **100% offline** by default
- Optionally syncs to **AWS cloud**
- Keeps **local Hive as primary storage**
- Provides **cross-device sync** when enabled
- Requires **no breaking changes** to existing code
- Gives users **full control** over cloud sync
