# AWS SNS Push Notifications Setup

This document explains how the AWS SNS push notification system replaces Firebase Cloud Messaging in CashSense.

## Architecture Overview

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────┐
│  Flutter App    │────────▶│  Node.js Backend │────────▶│  AWS SNS    │
│                 │         │  (api.dhdsoftware.com)│         │             │
│ • Get token     │         │  • Register device│         │ • Store ARN │
│ • Register      │         │  • Send to SNS    │         │ • Send push │
│ • Display local │         │  • Store in DB    │         │             │
└─────────────────┘         └──────────────────┘         └─────────────┘
         │                                                       │
         └───────────────────────────────────────────────────────┘
                    Push notification delivered
```

## Components

### 1. Flutter App (`aws_notification_service.dart`)
- **Purpose**: Handle device token registration and display notifications
- **Key Features**:
  - Requests notification permissions (Android & iOS)
  - Gets device token from platform
  - Registers token with backend
  - Displays local notifications when received
  - Handles notification taps (navigate to bill details)

### 2. Backend Server (`server.js`)
- **Endpoints**:
  - `POST /api/users/:userId/device` - Register device token with SNS
  - `POST /api/users/:userId/notify` - Send push notification
  - `GET /health` - Health check

### 3. AWS SNS
- **Platform Applications**:
  - Android: Uses FCM (Firebase Cloud Messaging) tokens
  - iOS: Uses APNS (Apple Push Notification Service)
- **Endpoint ARNs**: Stored per device in DynamoDB

## Setup Instructions

### Step 1: AWS SNS Configuration

1. **Create SNS Platform Applications**:
   ```bash
   # For Android (using FCM)
   aws sns create-platform-application \
     --name CashSense-Android \
     --platform GCM \
     --attributes PlatformCredential=<FCM_SERVER_KEY>
   
   # For iOS (using APNS)
   aws sns create-platform-application \
     --name CashSense-iOS \
     --platform APNS \
     --attributes PlatformCredential=<P12_CERT_BASE64>
   ```

2. **Note the ARNs** returned:
   - Android ARN: `arn:aws:sns:us-east-1:123456789012:app/GCM/CashSense-Android`
   - iOS ARN: `arn:aws:sns:us-east-1:123456789012:app/APNS/CashSense-iOS`

### Step 2: Backend Environment Variables

Add to `cashsense-backend/.env`:

```bash
# AWS SNS Configuration
SNS_ANDROID_ARN=arn:aws:sns:us-east-1:123456789012:app/GCM/CashSense-Android
SNS_IOS_ARN=arn:aws:sns:us-east-1:123456789012:app/APNS/CashSense-iOS

# AWS Credentials (if not using IAM role)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
```

### Step 3: Device Token Generation

#### Android (FCM Token)
Even though we removed Firebase from the app, Android still uses FCM tokens for push notifications. You have two options:

**Option A: Keep Firebase Messaging for token only**
```yaml
# pubspec.yaml
dependencies:
  firebase_core: ^2.24.2
  firebase_messaging: ^14.7.9
```

```dart
// Get FCM token
final fcmToken = await FirebaseMessaging.instance.getToken();
```

**Option B: Use alternative push service**
- OneSignal
- Pushy.me
- Custom implementation

#### iOS (APNS Token)
iOS uses native APNS tokens:

```dart
// Request APNS token
final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
```

### Step 4: Test Notifications

1. **Start the backend**:
   ```bash
   cd cashsense-backend
   npm start
   ```

2. **Register a test device**:
  ```bash
  curl -X POST https://d-dx8q9o5bja.execute-api.us-east-1.amazonaws.com/api/users/test-user-123/device \
    -H "Content-Type: application/json" \
    -d '{
      "deviceToken": "your-device-token",
      "platform": "android"
    }'
  ```

3. **Send a test notification**:
  ```bash
  curl -X POST https://d-dx8q9o5bja.execute-api.us-east-1.amazonaws.com/api/users/test-user-123/notify \
    -H "Content-Type: application/json" \
    -d '{
      "title": "Test Notification",
      "body": "This is a test",
      "data": {"type": "test"}
    }'
  ```

## How It Works

### Registration Flow

1. **App Launch**:
   ```dart
   await AWSNotificationService().init();
   ```

2. **Permission Request**:
   - Android: Requests notification permission
   - iOS: Requests alert, badge, and sound permissions

3. **Token Generation**:
   - Platform generates device token (FCM for Android, APNS for iOS)

4. **Backend Registration**:
   ```
   POST /api/users/{userId}/device
   {
     "deviceToken": "abc123...",
     "platform": "android"
   }
   ```

5. **SNS Endpoint Creation**:
   - Backend calls `sns.createPlatformEndpoint()`
   - Returns endpoint ARN
   - Stores in DynamoDB Users table

### Sending Notifications

1. **Trigger Event** (e.g., bill due tomorrow):
   ```javascript
   await notifyUser(userId, {
     title: 'Bill Due Tomorrow',
     body: 'Netflix subscription ($15.99)',
     data: { billId: 'bill-123' }
   });
   ```

2. **Backend Processing**:
   - Retrieves user's endpoint ARN from DynamoDB
   - Formats message for platform (Android/iOS)
   - Sends via `sns.publish()`

3. **App Receives**:
   - Platform delivers push notification
   - User taps notification
   - `_onNotificationTap()` called
   - Navigates to bill detail screen

## Code Examples

### Send Notification from Flutter

```dart
final notificationService = AWSNotificationService();

await notificationService.sendTestNotification();
```

### Send from Backend

```javascript
const AWS = require('aws-sdk');
const sns = new AWS.SNS({ region: 'us-east-1' });

const params = {
  Message: JSON.stringify({
    default: 'Default message',
    GCM: JSON.stringify({
      notification: {
        title: 'Bill Reminder',
        body: 'Your Netflix bill is due tomorrow'
      },
      data: { billId: 'bill-123' }
    })
  }),
  MessageStructure: 'json',
  TargetArn: endpointArn
};

await sns.publish(params).promise();
```

## Troubleshooting

### "Device token is null"
- **Android**: Ensure FCM is configured in Firebase Console
- **iOS**: Ensure APNS certificates are properly configured

### "Failed to register device"
- Check backend is running: `curl https://d-dx8q9o5bja.execute-api.us-east-1.amazonaws.com/health`
- Verify AWS credentials are set
- Check SNS ARNs are correct

### "Notification not displayed"
- Check notification permissions are granted
- Verify endpoint ARN exists in DynamoDB
- Check AWS SNS delivery logs

### "App crashes on notification tap"
- Ensure `navigatorKey` is set in MaterialApp
- Verify bill exists in database before navigation

## Migration from Firebase

### Removed Dependencies
```yaml
# These were removed:
# firebase_core: ^2.24.2
# firebase_messaging: ^14.7.9
# firebase_analytics: ^10.8.0
# firebase_crashlytics: ^3.4.9
```

### What Changed
- ❌ Firebase Cloud Messaging → ✅ AWS SNS
- ❌ `FirebaseMessaging.instance` → ✅ `AWSNotificationService()`
- ❌ Firebase token → ✅ Platform token + SNS endpoint ARN
- ❌ Firebase Console → ✅ AWS SNS Console

### What Stayed the Same
- Local notification display (flutter_local_notifications)
- Notification tap handling
- UI/UX for users

## Production Checklist

- [ ] AWS SNS platform applications created
- [ ] Environment variables configured
- [ ] Device token generation implemented
- [ ] Backend endpoints tested
- [ ] Notification permissions working
- [ ] Navigation on tap working
- [ ] iOS APNS certificates uploaded
- [ ] Android FCM server key configured
- [ ] DynamoDB Users table has deviceTokens field
- [ ] SNS delivery logs monitored

## Cost Considerations

AWS SNS pricing (as of 2024):
- First 1 million mobile push notifications: **FREE**
- Beyond 1 million: **$0.50 per million**

Example:
- 10,000 users
- 2 notifications per day
- 600,000 notifications/month
- **Cost: $0** (within free tier)

## Security Notes

1. **Never expose SNS ARNs** in client code
2. **Validate user ownership** before sending notifications
3. **Rate limit** notification endpoints
4. **Encrypt device tokens** in database
5. **Use IAM roles** for backend, not access keys

## Next Steps

1. Implement proper device token generation
2. Test on physical devices (Android & iOS)
3. Set up AWS SNS monitoring
4. Implement notification scheduling for bill reminders
5. Add analytics for notification engagement

---

**Status**: ✅ Backend ready, Flutter integration complete, awaiting device token implementation
