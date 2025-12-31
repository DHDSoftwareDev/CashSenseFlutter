// setup-cashsense-aws.js
// Run this script once to set up all AWS resources for CashSense

const AWS = require('aws-sdk');
const readline = require('readline');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

function question(prompt) {
  return new Promise(resolve => {
    rl.question(prompt, resolve);
  });
}

async function setup() {
  console.log('🚀 CashSense AWS Setup\n');
  console.log('This script will set up all necessary AWS resources.\n');
  
  // Get credentials
  const accessKeyId = await question('Enter your AWS Access Key ID: ');
  const secretAccessKey = await question('Enter your AWS Secret Access Key: ');
  const region = await question('Enter AWS region (default: us-east-1): ') || 'us-east-1';
  
  // Configure AWS
  AWS.config.update({
    region: region,
    accessKeyId: accessKeyId,
    secretAccessKey: secretAccessKey
  });
  
  console.log('\n✅ AWS credentials configured\n');
  
  try {
    // Step 1: Create S3 Bucket
    console.log('📦 Step 1: Creating S3 bucket for backups...');
    const s3 = new AWS.S3();
    const bucketName = `cashsense-backups-${Date.now()}`;
    
    try {
      await s3.createBucket({
        Bucket: bucketName,
        CreateBucketConfiguration: region !== 'us-east-1' ? {
          LocationConstraint: region
        } : undefined
      }).promise();
      
      // Enable versioning
      await s3.putBucketVersioning({
        Bucket: bucketName,
        VersioningConfiguration: {
          Status: 'Enabled'
        }
      }).promise();
      
      // Enable encryption
      await s3.putBucketEncryption({
        Bucket: bucketName,
        ServerSideEncryptionConfiguration: {
          Rules: [{
            ApplyServerSideEncryptionByDefault: {
              SSEAlgorithm: 'AES256'
            }
          }]
        }
      }).promise();
      
      console.log(`✅ S3 bucket created: ${bucketName}`);
    } catch (error) {
      if (error.code === 'BucketAlreadyExists' || error.code === 'BucketAlreadyOwnedByYou') {
        console.log('⚠️  Bucket already exists, using existing bucket');
      } else {
        throw error;
      }
    }
    
    // Step 2: Create DynamoDB Tables
    console.log('\n📊 Step 2: Creating DynamoDB tables...');
    const dynamodb = new AWS.DynamoDB();
    
    const tables = [
      {
        TableName: 'CashSense-Users',
        KeySchema: [
          { AttributeName: 'userId', KeyType: 'HASH' }
        ],
        AttributeDefinitions: [
          { AttributeName: 'userId', AttributeType: 'S' }
        ],
        BillingMode: 'PAY_PER_REQUEST'
      },
      {
        TableName: 'CashSense-Transactions',
        KeySchema: [
          { AttributeName: 'userId', KeyType: 'HASH' },
          { AttributeName: 'transactionId', KeyType: 'RANGE' }
        ],
        AttributeDefinitions: [
          { AttributeName: 'userId', AttributeType: 'S' },
          { AttributeName: 'transactionId', AttributeType: 'S' }
        ],
        BillingMode: 'PAY_PER_REQUEST'
      },
      {
        TableName: 'CashSense-Categories',
        KeySchema: [
          { AttributeName: 'userId', KeyType: 'HASH' },
          { AttributeName: 'categoryId', KeyType: 'RANGE' }
        ],
        AttributeDefinitions: [
          { AttributeName: 'userId', AttributeType: 'S' },
          { AttributeName: 'categoryId', AttributeType: 'S' }
        ],
        BillingMode: 'PAY_PER_REQUEST'
      }
    ];
    
    for (const tableConfig of tables) {
      try {
        await dynamodb.createTable(tableConfig).promise();
        console.log(`✅ Table created: ${tableConfig.TableName}`);
        
        // Wait for table to be active
        await dynamodb.waitFor('tableExists', {
          TableName: tableConfig.TableName
        }).promise();
      } catch (error) {
        if (error.code === 'ResourceInUseException') {
          console.log(`⚠️  Table ${tableConfig.TableName} already exists`);
        } else {
          throw error;
        }
      }
    }
    
    // Step 3: Set up SNS for notifications
    console.log('\n🔔 Step 3: Setting up SNS for push notifications...');
    const sns = new AWS.SNS();
    
    const setupSNS = await question('Do you want to set up push notifications now? (y/n): ');
    
    let androidArn = '';
    let iosArn = '';
    
    if (setupSNS.toLowerCase() === 'y') {
      // Android setup
      const setupAndroid = await question('Set up Android notifications? (y/n): ');
      if (setupAndroid.toLowerCase() === 'y') {
        const fcmServerKey = await question('Enter your FCM Server Key from Firebase Console: ');
        
        try {
          const androidApp = await sns.createPlatformApplication({
            Name: 'CashSense-Android',
            Platform: 'GCM',
            Attributes: {
              'PlatformCredential': fcmServerKey
            }
          }).promise();
          
          androidArn = androidApp.PlatformApplicationArn;
          console.log(`✅ Android push notifications configured`);
        } catch (error) {
          console.log('⚠️  Error setting up Android notifications:', error.message);
        }
      }
      
      // iOS setup
      const setupIOS = await question('Set up iOS notifications? (y/n): ');
      if (setupIOS.toLowerCase() === 'y') {
        console.log('⚠️  iOS setup requires APNS certificate. Skipping for now.');
        console.log('   You can set this up later through AWS Console → SNS → Mobile → Push notifications');
      }
    }
    
    // Step 4: Create lifecycle policy for S3
    console.log('\n🗂️  Step 4: Setting up S3 lifecycle policy...');
    try {
      await s3.putBucketLifecycleConfiguration({
        Bucket: bucketName,
        LifecycleConfiguration: {
          Rules: [{
            Id: 'cleanup-old-backups',
            Status: 'Enabled',
            Prefix: '',
            Transitions: [
              {
                Days: 7,
                StorageClass: 'STANDARD_IA'
              },
              {
                Days: 30,
                StorageClass: 'GLACIER'
              }
            ],
            Expiration: {
              Days: 365
            }
          }]
        }
      }).promise();
      console.log('✅ S3 lifecycle policy configured (old backups will auto-archive)');
    } catch (error) {
      console.log('⚠️  Error setting up lifecycle policy:', error.message);
    }
    
    // Step 5: Generate .env file
    console.log('\n📝 Step 5: Generating configuration file...');
    const fs = require('fs');
    
    const envContent = `# AWS Configuration for CashSense
# Generated: ${new Date().toISOString()}

AWS_REGION=${region}
AWS_ACCESS_KEY_ID=${accessKeyId}
AWS_SECRET_ACCESS_KEY=${secretAccessKey}

# S3 Bucket
S3_BUCKET=${bucketName}

# SNS Platform ARNs
SNS_ANDROID_ARN=${androidArn}
SNS_IOS_ARN=${iosArn}

# DynamoDB Tables
DYNAMODB_USERS_TABLE=CashSense-Users
DYNAMODB_TRANSACTIONS_TABLE=CashSense-Transactions
DYNAMODB_CATEGORIES_TABLE=CashSense-Categories
`;
    
    fs.writeFileSync('.env', envContent);
    console.log('✅ Configuration saved to .env file');
    
    // Summary
    console.log('\n' + '='.repeat(60));
    console.log('🎉 Setup Complete!');
    console.log('='.repeat(60));
    console.log('\n📋 Resources Created:');
    console.log(`   ✓ S3 Bucket: ${bucketName}`);
    console.log('   ✓ DynamoDB Tables:');
    console.log('     - CashSense-Users');
    console.log('     - CashSense-Transactions');
    console.log('     - CashSense-Categories');
    if (androidArn) {
      console.log('   ✓ SNS Platform Application (Android)');
    }
    console.log('\n📄 Configuration file: .env');
    console.log('\n🚀 Next Steps:');
    console.log('   1. Install dependencies: npm install aws-sdk dotenv');
    console.log('   2. Export your Firebase data');
    console.log('   3. Run import script to migrate data');
    console.log('   4. Update your app code to use AWS');
    console.log('   5. Test everything thoroughly');
    console.log('\n💡 Tip: Keep your .env file secure and never commit it to git!');
    console.log('\n');
    
  } catch (error) {
    console.error('\n❌ Setup failed:', error.message);
    console.error('\nFull error:', error);
  } finally {
    rl.close();
  }
}

// Run setup
setup();