// import-to-aws.js
// Import Firebase data to AWS DynamoDB and S3

require('dotenv').config();
const AWS = require('aws-sdk');
const fs = require('fs');
const path = require('path');

// Configure AWS
AWS.config.update({
  region: process.env.AWS_REGION,
  accessKeyId: process.env.AWS_ACCESS_KEY_ID,
  secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
});

const dynamodb = new AWS.DynamoDB.DocumentClient();
const s3 = new AWS.S3();

const TABLES = {
  USERS: process.env.DYNAMODB_USERS_TABLE || 'CashSense-Users',
  TRANSACTIONS: process.env.DYNAMODB_TRANSACTIONS_TABLE || 'CashSense-Transactions',
  CATEGORIES: process.env.DYNAMODB_CATEGORIES_TABLE || 'CashSense-Categories'
};

async function importUsers(exportDir) {
  console.log('\n👥 Importing users...');
  
  const filePath = path.join(exportDir, 'users.json');
  if (!fs.existsSync(filePath)) {
    console.log('⚠️  No users.json found, skipping...');
    return 0;
  }
  
  const users = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  let imported = 0;
  
  for (const user of users) {
    try {
      const item = {
        userId: user.id || user.userId,
        email: user.email,
        displayName: user.displayName || user.name,
        createdAt: user.createdAt || new Date().toISOString(),
        settings: user.settings || {},
        deviceTokens: user.deviceTokens || []
      };
      
      await dynamodb.put({
        TableName: TABLES.USERS,
        Item: item
      }).promise();
      
      imported++;
      console.log(`  ✓ Imported user: ${item.email || item.userId}`);
    } catch (error) {
      console.error(`  ✗ Failed to import user ${user.id}:`, error.message);
    }
  }
  
  console.log(`✅ Imported ${imported}/${users.length} users`);
  return imported;
}

async function importTransactions(exportDir) {
  console.log('\n💳 Importing transactions...');
  
  const filePath = path.join(exportDir, 'transactions.json');
  if (!fs.existsSync(filePath)) {
    console.log('⚠️  No transactions.json found, skipping...');
    return 0;
  }
  
  const transactions = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  let imported = 0;
  
  // Batch write for better performance (max 25 items per batch)
  const batches = [];
  for (let i = 0; i < transactions.length; i += 25) {
    batches.push(transactions.slice(i, i + 25));
  }
  
  for (const batch of batches) {
    const requests = batch.map(txn => ({
      PutRequest: {
        Item: {
          userId: txn.userId,
          transactionId: txn.id || txn.transactionId || `txn_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
          amount: parseFloat(txn.amount),
          category: txn.category || 'Uncategorized',
          date: txn.date || txn.createdAt || new Date().toISOString(),
          description: txn.description || '',
          type: txn.type || 'expense',
          createdAt: txn.createdAt || new Date().toISOString()
        }
      }
    }));
    
    try {
      await dynamodb.batchWrite({
        RequestItems: {
          [TABLES.TRANSACTIONS]: requests
        }
      }).promise();
      
      imported += requests.length;
      console.log(`  ✓ Imported batch of ${requests.length} transactions`);
    } catch (error) {
      console.error('  ✗ Failed to import batch:', error.message);
    }
  }
  
  console.log(`✅ Imported ${imported}/${transactions.length} transactions`);
  return imported;
}

async function importCategories(exportDir) {
  console.log('\n📁 Importing categories...');
  
  const filePath = path.join(exportDir, 'categories.json');
  if (!fs.existsSync(filePath)) {
    console.log('⚠️  No categories.json found, skipping...');
    return 0;
  }
  
  const categories = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  let imported = 0;
  
  for (const category of categories) {
    try {
      const item = {
        userId: category.userId,
        categoryId: category.id || category.categoryId,
        name: category.name,
        icon: category.icon || '📌',
        color: category.color || '#000000',
        type: category.type || 'expense',
        createdAt: category.createdAt || new Date().toISOString()
      };
      
      await dynamodb.put({
        TableName: TABLES.CATEGORIES,
        Item: item
      }).promise();
      
      imported++;
      console.log(`  ✓ Imported category: ${item.name}`);
    } catch (error) {
      console.error(`  ✗ Failed to import category ${category.id}:`, error.message);
    }
  }
  
  console.log(`✅ Imported ${imported}/${categories.length} categories`);
  return imported;
}

async function createInitialBackups(exportDir) {
  console.log('\n💾 Creating initial backups in S3...');
  
  const usersPath = path.join(exportDir, 'users.json');
  const transactionsPath = path.join(exportDir, 'transactions.json');
  
  if (!fs.existsSync(usersPath)) {
    console.log('⚠️  No users data to backup');
    return 0;
  }
  
  const users = JSON.parse(fs.readFileSync(usersPath, 'utf8'));
  const allTransactions = fs.existsSync(transactionsPath) 
    ? JSON.parse(fs.readFileSync(transactionsPath, 'utf8'))
    : [];
  
  let backedUp = 0;
  
  for (const user of users) {
    const userId = user.id || user.userId;
    const userTransactions = allTransactions.filter(t => t.userId === userId);
    
    const backupData = {
      user: user,
      transactions: userTransactions,
      timestamp: new Date().toISOString(),
      source: 'firebase-migration'
    };
    
    try {
      await s3.putObject({
        Bucket: process.env.S3_BUCKET,
        Key: `users/${userId}/migration-backup-${Date.now()}.json`,
        Body: JSON.stringify(backupData),
        ContentType: 'application/json',
        ServerSideEncryption: 'AES256',
        Metadata: {
          userId: userId,
          source: 'firebase-migration',
          backupDate: new Date().toISOString()
        }
      }).promise();
      
      backedUp++;
      console.log(`  ✓ Backed up data for user: ${user.email || userId}`);
    } catch (error) {
      console.error(`  ✗ Failed to backup user ${userId}:`, error.message);
    }
  }
  
  console.log(`✅ Created ${backedUp}/${users.length} backups in S3`);
  return backedUp;
}

async function verifyImport() {
  console.log('\n🔍 Verifying import...');
  
  try {
    // Count users
    const usersResult = await dynamodb.scan({
      TableName: TABLES.USERS,
      Select: 'COUNT'
    }).promise();
    console.log(`  ✓ Users in DynamoDB: ${usersResult.Count}`);
    
    // Count transactions
    const transactionsResult = await dynamodb.scan({
      TableName: TABLES.TRANSACTIONS,
      Select: 'COUNT'
    }).promise();
    console.log(`  ✓ Transactions in DynamoDB: ${transactionsResult.Count}`);
    
    // Count S3 backups
    const s3Result = await s3.listObjectsV2({
      Bucket: process.env.S3_BUCKET,
      Prefix: 'users/'
    }).promise();
    console.log(`  ✓ Backups in S3: ${s3Result.KeyCount}`);
    
    console.log('✅ Verification complete');
  } catch (error) {
    console.error('⚠️  Verification failed:', error.message);
  }
}

async function runImport() {
  console.log('🚀 Starting AWS Import\n');
  console.log('='.repeat(60));
  
  // Find the most recent export directory
  const exportDirs = fs.readdirSync('.')
    .filter(f => f.startsWith('firebase-export-'))
    .sort()
    .reverse();
  
  if (exportDirs.length === 0) {
    console.error('❌ No Firebase export directory found!');
    console.log('\n💡 Please run export-firebase-data.js first');
    process.exit(1);
  }
  
  const exportDir = exportDirs[0];
  console.log(`📁 Using export directory: ${exportDir}\n`);
  
  try {
    const stats = {
      users: await importUsers(exportDir),
      transactions: await importTransactions(exportDir),
      categories: await importCategories(exportDir),
      backups: await createInitialBackups(exportDir)
    };
    
    console.log('\n' + '='.repeat(60));
    console.log('✅ Import Complete!');
    console.log('='.repeat(60));
    console.log('\n📊 Summary:');
    console.log(`   • Users imported: ${stats.users}`);
    console.log(`   • Transactions imported: ${stats.transactions}`);
    console.log(`   • Categories imported: ${stats.categories}`);
    console.log(`   • S3 backups created: ${stats.backups}`);
    
    await verifyImport();
    
    console.log('\n🚀 Next Steps:');
    console.log('   1. Test the AWS Helper module with your app');
    console.log('   2. Update your app code to use AWS instead of Firebase');
    console.log('   3. Test notifications with SNS');
    console.log('   4. Once confident, disable Firebase services');
    console.log('\n💡 All your data is now in AWS and backed up in S3!');
    console.log('\n');
    
  } catch (error) {
    console.error('\n❌ Import failed:', error.message);
    console.error('\nFull error:', error);
    process.exit(1);
  }
}

// Check if .env file exists
if (!fs.existsSync('.env')) {
  console.error('❌ .env file not found!');
  console.log('\n💡 Please run setup-cashsense-aws.js first');
  process.exit(1);
}

// Run the import
runImport();