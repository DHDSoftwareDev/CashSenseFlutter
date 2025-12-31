# AWS Backup Setup Guide for CashSense

## Overview
Firebase has been completely removed from CashSense and replaced with AWS services for cloud backups. This guide explains how to set up and use the AWS backup system.

## Architecture

### Local-First with Cloud Backup
```
Flutter App (Hive Storage)
        ↓
   Local Backups (Always)
        ↓
   AWS S3 Backups (Optional - when logged in)
```

### Key Benefits
- ✅ **Offline-First**: All data is stored locally in Hive
- ✅ **Automatic Backups**: Daily automatic backups to both local storage and AWS S3
- ✅ **Manual Backups**: Create backups anytime from the app
- ✅ **Cross-Device Sync**: Restore backups on any device
- ✅ **Versioning**: Keep multiple backup versions
- ✅ **Secure**: Encrypted backups in AWS S3

## What Was Removed

### Firebase Services Removed
- ❌ firebase_core
- ❌ firebase_messaging
- ❌ firebase_analytics
      The backend will run on `https://d-dx8q9o5bja.execute-api.us-east-1.amazonaws.com` by default.
- ❌ firebase_remote_config
- ❌ cloud_firestore
- ❌ firebase_auth
- ❌ firebase_storage
- ❌ firebase_app_check

### Configuration Files Removed
- ❌ `google-services.json` (Android)
      static const String baseUrl = 'https://d-dx8q9o5bja.execute-api.us-east-1.amazonaws.com/api';
- ❌ `firebase.json`
- ❌ `firebase-service-account.json`
- ❌ Firebase Gradle plugins
- ❌ Firebase iOS Pods

## AWS Services Used

### 1. AWS S3 (Backup Storage)
- Stores encrypted backup files
- Automatic versioning
- Lifecycle policies for old backups

### 2. AWS DynamoDB (Optional Sync)
- Real-time data synchronization
- Categories, transactions, accounts, bills
- Bidirectional sync

### 3. AWS Cognito (Authentication)
- User authentication
- Secure login/signup
- Password management

### 4. AWS SNS (Push Notifications)
- Bill reminders
- Payment due notifications
- Device token management

## Backend Setup

### Prerequisites
1. AWS Account with access keys
2. Node.js backend server (included in `cashsense-backend/`)
3. Environment variables configured

### Backend API Endpoints

The backend provides the following endpoints:

#### Backup Endpoints
```
POST   /api/backups              - Create a new backup
GET    /api/backups/:userId      - List all backups for user
GET    /api/backups/:userId/:id  - Download specific backup
DELETE /api/backups/:userId/:id  - Delete a backup
GET    /api/backups/:userId/:id/info - Get backup metadata
```

#### Sync Endpoints
```
GET    /api/users/:userId           - Get user data
POST   /api/users                   - Create user
PUT    /api/users/:userId           - Update user
GET    /api/transactions/:userId    - Get transactions
POST   /api/transactions            - Create transaction
GET    /api/categories/:userId      - Get categories
POST   /api/categories              - Create category
```

### Environment Variables

Create a `.env` file in the `cashsense-backend/` directory:

```env
# AWS Configuration
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key

# S3 Configuration
S3_BUCKET_NAME=cashsense-backups
S3_BACKUP_PREFIX=backups/

# DynamoDB Tables
DYNAMODB_USERS_TABLE=cashsense-users
DYNAMODB_TRANSACTIONS_TABLE=cashsense-transactions
DYNAMODB_CATEGORIES_TABLE=cashsense-categories
DYNAMODB_ACCOUNTS_TABLE=cashsense-accounts
DYNAMODB_BILLS_TABLE=cashsense-bills

      ```bash
      curl https://d-dx8q9o5bja.execute-api.us-east-1.amazonaws.com/api/health
      ```
# Cognito Configuration
COGNITO_USER_POOL_ID=your_user_pool_id
COGNITO_CLIENT_ID=your_client_id
COGNITO_REGION=us-east-1

# Server Configuration
PORT=3000
NODE_ENV=production
```

### Starting the Backend

```bash
cd cashsense-backend
npm install
npm start
```

The backend will run on `https://d-dx8q9o5bja.execute-api.us-east-1.amazonaws.com` by default.

## Flutter App Configuration

### 1. Update AWS Service Base URL

Edit `lib/services/aws_service.dart`:

```dart
// For local development
static const String baseUrl = 'https://d-dx8q9o5bja.execute-api.us-east-1.amazonaws.com/api';

// For Android emulator
static const String baseUrl = 'http://10.0.2.2:3000/api';

// For production (deploy backend to AWS)
static const String baseUrl = 'https://your-api.amazonaws.com/api';
```

### 2. Update Cloud Backup Service

Edit `lib/services/cloud_backup_service.dart`:

```dart
static const String baseUrl = 'https://your-api.amazonaws.com/api';
```

### 3. Configure Amplify

Create `.env` file in the Flutter project root:

```env
COGNITO_USER_POOL_ID=your_user_pool_id
COGNITO_CLIENT_ID=your_client_id
COGNITO_REGION=us-east-1
```

## Using the Backup System

### Automatic Backups

Automatic backups run daily for premium users:

1. Enable in Settings → Backup Settings
2. Toggle "Enable Automatic Backups"
3. Backups occur daily at midnight
4. Saves to both local storage and AWS S3

### Manual Backups

Create a backup anytime:

```dart
import 'package:cashsenseflutter/services/cloud_backup_service.dart';

final backupService = CloudBackupService();
await backupService.createBackup(backupName: 'my_backup');
```

### Listing Backups

View all available backups:

```dart
final backups = await backupService.listBackups();
for (final backup in backups) {
  print('Backup: ${backup['backupName']}');
  print('Date: ${backup['timestamp']}');
  print('Size: ${backup['size']} bytes');
}
```

### Restoring Backups

Restore from a specific backup:

```dart
await backupService.restoreBackup(backupId);
```

### Deleting Backups

Remove old backups:

```dart
await backupService.deleteBackup(backupId);
```

## Local Backup Behavior

### Android
- Saves to: `/storage/emulated/0/Download/CashSense/`
- Keeps last 3 automatic backups
- Files named: `cashsense_auto_backup_MM-DD-YY_HH-MM_AM.json`

### iOS
- Saves to: `Documents/CashSense/`
- Keeps last 3 automatic backups
- Accessible via Files app

## AWS S3 Backup Structure

```
s3://cashsense-backups/
  └── backups/
      └── {userId}/
          ├── auto_backup_2025-12-12_03-15-pm.json
          ├── manual_backup_2025-12-11.json
          └── ...
```

## Security Considerations

### Data Encryption
- All backups are encrypted at rest in S3
- Use AWS KMS for encryption keys
- Enable S3 bucket encryption

### Access Control
- Use IAM roles with least privilege
- Enable MFA for AWS console access
- Rotate access keys regularly

### Network Security
- Use HTTPS for all API calls
- Implement rate limiting
- Add API authentication tokens

## Troubleshooting

### Backup Fails
1. Check internet connection
2. Verify user is logged in: `await UserAuthService().isLoggedIn()`
3. Check backend is running: `curl https://d-dx8q9o5bja.execute-api.us-east-1.amazonaws.com/api/health`
4. Review logs: `debugPrint` statements in services

### Restore Fails
1. Verify backup ID exists: `await backupService.listBackups()`
2. Check backup is not corrupted
3. Ensure sufficient storage space
4. Try manual JSON import/export

### AWS Connection Issues
1. Verify AWS credentials in `.env`
2. Check AWS region is correct
3. Verify S3 bucket exists and is accessible
4. Check IAM permissions

## Migration from Firebase

If you have existing Firebase data:

1. Export Firebase data using `export-firebase-data.js`
2. Import to AWS using `import-to-aws.js`
3. Verify data in DynamoDB tables
4. Test backup/restore functionality

## Cost Optimization

### S3 Storage Costs
- Use lifecycle policies to delete old backups
- Keep last 30 days of backups
- Archive to Glacier for long-term storage

### DynamoDB Costs
- Use on-demand billing for low traffic
- Set up auto-scaling for production
- Monitor read/write capacity units

### SNS Costs
- Free tier: 1 million requests/month
- Monitor usage in AWS console

## Production Deployment

### Deploy Backend to AWS

1. **Use AWS Elastic Beanstalk**
   ```bash
   eb init cashsense-backend
   eb create cashsense-production
   eb deploy
   ```

2. **Use AWS Lambda + API Gateway**
   - Convert to serverless functions
   - Use AWS SAM or Serverless Framework

3. **Use AWS ECS/Fargate**
   - Containerize with Docker
   - Deploy to ECS cluster

### Update Flutter App
1. Change base URL to production endpoint
2. Test all backup operations
3. Deploy to App Store / Play Store

## Support

For issues or questions:
- Check backend logs: `npm run logs`
- Review Flutter logs: Run with `--verbose`
- Contact: support@dhdsoftware.com

## License

MIT License - See LICENSE file for details
