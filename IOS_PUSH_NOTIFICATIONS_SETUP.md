# iOS Push Notifications Setup with AWS SNS

## Overview
This guide walks you through setting up Apple Push Notification Service (APNS) with AWS SNS for your CashSense iOS app.

## Prerequisites
- Apple Developer Account (paid membership required)
- AWS Account with SNS access
- Xcode installed on Mac
- Your app's Bundle ID

## Step 1: Get APNS Authentication (P8 Key or P12 Certificate)

### Option A: Using P8 Key (Recommended - If you already have one)

If you already have a P8 key, you can skip certificate creation. You need:
1. **P8 file** - Your `.p8` key file
2. **Key ID** - 10-character identifier (e.g., `ABC123DEFG`)
3. **Team ID** - Your Apple Developer Team ID (e.g., `XYZ987WXYZ`)
4. **Bundle ID** - Your app's bundle identifier (e.g., `name.dhdsoftware.cashsense.CashSenseMM`)

**To find these values:**
1. Go to [Apple Developer Portal](https://developer.apple.com/account/)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Keys** → Select your key
4. Note the **Key ID** (10 characters)
5. Go to **Membership** → Note your **Team ID** (10 characters)
6. The P8 file should be something like `AuthKey_ABC123DEFG.p8`

**Enable Push Notifications for your App ID:**
1. Go to **Identifiers** → Select your app's App ID
2. Check **Push Notifications** capability
3. Click **Save**

### Option B: Create New P12 Certificate (If you don't have P8)

#### 1.1 Generate Certificate Signing Request (CSR)

1. Open **Keychain Access** on your Mac (Applications → Utilities → Keychain Access)
2. Go to **Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority**
3. Fill in the form:
   - User Email Address: Your email
   - Common Name: `CashSense APNS`
   - Request is: **Saved to disk**
   - Let me specify key pair information: **Unchecked**
4. Click **Continue** and save the file (CertificateSigningRequest.certSigningRequest)

#### 1.2 Create APNS Certificate

1. Go to [Apple Developer Portal](https://developer.apple.com/account/)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Identifiers** → Select your app's App ID (e.g., `name.dhdsoftware.cashsense.CashSenseMM`)
4. Scroll to **Push Notifications** and click **Configure**
5. Under **Production SSL Certificate**, click **Create Certificate**
6. Upload your CSR file from Step 1.1
7. Download the certificate (aps_production.cer)
8. Double-click the downloaded certificate to install it in Keychain Access

#### 1.3 Export P12 Certificate

1. Open **Keychain Access**
2. In the "login" keychain, under "My Certificates", find the certificate named "Apple Push Services: [your bundle ID]"
3. Right-click the certificate and select **Export**
4. Save as: `CashSense_APNS_Production.p12`
5. Set a password (you'll need this for AWS SNS setup)
6. Save the file

## Step 2: Configure Xcode Project

### 2.1 Enable Push Notifications Capability

1. Open your project in Xcode: `open ios/Runner.xcworkspace`
2. Select the **Runner** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **Push Notifications**
6. Add **Background Modes** and check:
   - Remote notifications
   - Background fetch

### 2.2 Update Info.plist (Already configured)

The following is already set up in `ios/Runner/Info.plist`:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
    <string>fetch</string>
</array>
```

### 2.3 Verify AppDelegate.swift (Already configured)

The AppDelegate has been updated to:
- Request APNS authorization
- Register for remote notifications
- Handle device token registration
- Send token to Flutter via MethodChannel

## Step 3: Configure AWS SNS

### 3.1 Create SNS Platform Application

#### Option A: Using P8 Key (Recommended - Token-based Authentication)

1. Go to [AWS SNS Console](https://console.aws.amazon.com/sns/)
2. Click **Push notifications → Platform applications**
3. Click **Create platform application**
4. Fill in the details:
   - **Application name**: `CashSenseiOS`
   - **Push notification platform**: Apple iOS
   - **Used signing credentials**: Token
   - **Signing key**: Paste the contents of your `.p8` file
   - **Key ID**: Enter your 10-character Key ID (from Apple Developer Portal)
   - **Team ID**: Enter your 10-character Team ID (from Apple Developer Portal)
   - **Bundle ID**: `name.dhdsoftware.cashsense.CashSenseMM` (your app's bundle ID)
   - **Type**: Production
5. Click **Create platform application**
6. Copy the **ARN** (it looks like: `arn:aws:sns:us-east-1:123456789:app/APNS/CashSenseiOS`)

**To find your Key ID and Team ID:**
- Key ID: Go to Apple Developer Portal → Certificates, Identifiers & Profiles → Keys → Select your key → Copy the Key ID (10 characters)
- Team ID: Go to Apple Developer Portal → Membership → Copy the Team ID (10 characters)

#### Option B: Using P12 Certificate (Legacy - Certificate-based Authentication)

1. Go to [AWS SNS Console](https://console.aws.amazon.com/sns/)
2. Click **Push notifications → Platform applications**
3. Click **Create platform application**
4. Fill in the details:
   - **Application name**: `CashSenseiOS`
   - **Push notification platform**: Apple iOS
   - **Used signing credentials**: Certificate
   - **Choose a file to upload**: Upload your `.p12` file
   - **Password**: Enter the password you set when exporting the P12
   - **Type**: Production (or Sandbox for testing)
5. Click **Create platform application**
6. Copy the **ARN** (it looks like: `arn:aws:sns:us-east-1:123456789:app/APNS/CashSenseiOS`)

**Note**: P8 keys are recommended because:
- No expiration (P12 certificates expire annually)
- One key works for all apps
- Easier to manage and rotate

### 3.2 Update Backend .env File

Edit `cashsense-backend/.env`:

```env
SNS_IOS_ARN=arn:aws:sns:us-east-1:YOUR_ACCOUNT:app/APNS/CashSenseiOS
```

### 3.3 Update IAM Permissions

Ensure your AWS IAM user/role has these SNS permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sns:CreatePlatformEndpoint",
        "sns:DeleteEndpoint",
        "sns:GetEndpointAttributes",
        "sns:SetEndpointAttributes",
        "sns:Publish"
      ],
      "Resource": "arn:aws:sns:us-east-1:*:app/APNS/*"
    }
  ]
}
```

## Step 4: Test Push Notifications

### 4.1 Build and Run on Physical iOS Device

**Important**: Push notifications only work on physical devices, not simulators.

```bash
flutter clean
cd ios && pod install && cd ..
flutter run --release
```

### 4.2 Register Device

1. Launch the app on your iPhone/iPad
2. When prompted, allow notifications
3. Log in to your CashSense account
4. The app will automatically register the device with AWS SNS

Check logs for:
```
✅ APNS Device Token: abc123...
📱 Registering device with AWS SNS
✅ Device registered with AWS SNS
```

### 4.3 Send Test Notification

From Flutter:
```dart
import 'package:cashsenseflutter/services/aws_notification_service.dart';

// Send test notification
await AWSNotificationService().sendTestNotification();
```

From AWS Console:
1. Go to SNS → Platform applications → CashSenseiOS
2. Click on your device endpoint
3. Click **Publish message**
4. Enter a message and publish

## Step 5: Production Deployment

### 5.1 Archive and Submit to App Store

1. Update version in `pubspec.yaml`
2. Build for App Store:
   ```bash
   flutter build ios --release
   ```
3. Open Xcode: `open ios/Runner.xcworkspace`
4. Select **Any iOS Device** as target
5. Go to **Product → Archive**
6. Once archived, click **Distribute App**
7. Follow prompts to upload to App Store Connect

### 5.2 Switch to Production APNS

Ensure your SNS platform application uses **Production** certificate, not Sandbox.

## Troubleshooting

### Device Token Not Received

**Issue**: App doesn't receive APNS device token

**Solutions**:
1. Verify Push Notifications capability is enabled in Xcode
2. Check that app is running on a physical device (not simulator)
3. Ensure provisioning profile includes Push Notifications
4. Check console logs for errors

### Registration Fails

**Issue**: Device registration with AWS SNS fails

**Solutions**:
1. Verify SNS_IOS_ARN is correct in `.env`
2. Check AWS credentials have SNS permissions
3. Ensure backend server is running
4. Check backend logs for errors

### Notifications Not Appearing

**Issue**: Device is registered but notifications don't appear

**Solutions**:
1. Verify notification permissions are granted in iOS Settings
2. Check SNS endpoint is enabled (not disabled due to failed deliveries)
3. Test with AWS Console to isolate issue
4. Check if "Do Not Disturb" is enabled

### Certificate Issues

**Issue**: SNS rejects certificate or shows errors

**Solutions**:
1. Ensure P12 file is exported correctly from Keychain
2. Verify password matches what you set during export
3. Check certificate is for Production (not Development)
4. Ensure certificate hasn't expired

## Architecture Flow

```
iOS App (CashSense)
    ↓ (Requests APNS authorization)
Apple Push Notification Service (APNS)
    ↓ (Returns device token)
Flutter App (aws_notification_service.dart)
    ↓ (Registers device token)
Backend API (cashsense-backend/server.js)
    ↓ (Creates SNS endpoint)
AWS SNS
    ↓ (Stores device endpoint)
---
When sending notification:
Backend API → AWS SNS → APNS → iOS Device
```

## Code Reference

### Flutter
- `lib/services/aws_notification_service.dart` - Notification service
- `lib/main.dart` - Initialization

### iOS
- `ios/Runner/AppDelegate.swift` - APNS registration
- `ios/Runner/Info.plist` - Permissions and background modes

### Backend
- `cashsense-backend/server.js` - SNS integration
- `cashsense-backend/.env` - Configuration

## Security Best Practices

1. **Never commit certificates or P12 files to Git**
2. **Use environment variables for ARNs and credentials**
3. **Rotate APNS certificates before expiration**
4. **Use production certificates for App Store builds**
5. **Monitor SNS endpoints for disabled devices**
6. **Implement proper error handling for failed deliveries**

## Cost Optimization

- **APNS**: Free (Apple charges no fee for push notifications)
- **AWS SNS**: $0.50 per million mobile push notifications
- **First 1 million notifications per month**: Free

## Additional Resources

- [Apple Push Notification Service Documentation](https://developer.apple.com/documentation/usernotifications)
- [AWS SNS Mobile Push Documentation](https://docs.aws.amazon.com/sns/latest/dg/sns-mobile-push-notifications.html)
- [Flutter Local Notifications](https://pub.dev/packages/flutter_local_notifications)

## Support

For issues or questions:
- Check AWS SNS CloudWatch logs
- Review Xcode console output
- Contact: support@dhdsoftware.com
