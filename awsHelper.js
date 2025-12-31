// awsHelper.js - AWS Service Integration for CashSense
const AWS = require('aws-sdk');

// Configure AWS credentials
AWS.config.update({
  region: process.env.AWS_REGION || 'us-east-1',
  accessKeyId: process.env.AWS_ACCESS_KEY_ID,
  secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
});

const dynamodb = new AWS.DynamoDB.DocumentClient();
const s3 = new AWS.S3();
const sns = new AWS.SNS();

// Configuration
const CONFIG = {
  S3_BUCKET: process.env.S3_BUCKET || 'cashsense-backups',
  DYNAMODB_TABLES: {
    USERS: 'CashSense-Users',
    TRANSACTIONS: 'CashSense-Transactions',
    CATEGORIES: 'CashSense-Categories'
  },
  SNS_PLATFORM_ARN: {
    ANDROID: process.env.SNS_ANDROID_ARN,
    IOS: process.env.SNS_IOS_ARN
  }
};

// ============================================
// USER OPERATIONS
// ============================================

async function createUser(userId, userData) {
  const params = {
    TableName: CONFIG.DYNAMODB_TABLES.USERS,
    Item: {
      userId: userId,
      email: userData.email,
      displayName: userData.displayName,
      createdAt: new Date().toISOString(),
      settings: userData.settings || {},
      deviceTokens: []
    }
  };
  
  return dynamodb.put(params).promise();
}

async function getUser(userId) {
  const params = {
    TableName: CONFIG.DYNAMODB_TABLES.USERS,
    Key: { userId: userId }
  };
  
  const result = await dynamodb.get(params).promise();
  return result.Item;
}

async function updateUser(userId, updates) {
  const updateExpression = [];
  const expressionAttributeValues = {};
  const expressionAttributeNames = {};
  
  Object.keys(updates).forEach((key, index) => {
    updateExpression.push(`#attr${index} = :val${index}`);
    expressionAttributeNames[`#attr${index}`] = key;
    expressionAttributeValues[`:val${index}`] = updates[key];
  });
  
  const params = {
    TableName: CONFIG.DYNAMODB_TABLES.USERS,
    Key: { userId: userId },
    UpdateExpression: `SET ${updateExpression.join(', ')}`,
    ExpressionAttributeNames: expressionAttributeNames,
    ExpressionAttributeValues: expressionAttributeValues,
    ReturnValues: 'ALL_NEW'
  };
  
  const result = await dynamodb.update(params).promise();
  return result.Attributes;
}

// ============================================
// TRANSACTION OPERATIONS
// ============================================

async function createTransaction(userId, transaction) {
  const transactionId = transaction.id || `txn_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  
  const params = {
    TableName: CONFIG.DYNAMODB_TABLES.TRANSACTIONS,
    Item: {
      userId: userId,
      transactionId: transactionId,
      amount: transaction.amount,
      category: transaction.category,
      date: transaction.date || new Date().toISOString(),
      description: transaction.description || '',
      type: transaction.type, // 'income' or 'expense'
      createdAt: new Date().toISOString()
    }
  };
  
  await dynamodb.put(params).promise();
  return transactionId;
}

async function getUserTransactions(userId, limit = 100) {
  const params = {
    TableName: CONFIG.DYNAMODB_TABLES.TRANSACTIONS,
    KeyConditionExpression: 'userId = :userId',
    ExpressionAttributeValues: {
      ':userId': userId
    },
    Limit: limit,
    ScanIndexForward: false // Get most recent first
  };
  
  const result = await dynamodb.query(params).promise();
  return result.Items;
}

async function getTransaction(userId, transactionId) {
  const params = {
    TableName: CONFIG.DYNAMODB_TABLES.TRANSACTIONS,
    Key: {
      userId: userId,
      transactionId: transactionId
    }
  };
  
  const result = await dynamodb.get(params).promise();
  return result.Item;
}

async function updateTransaction(userId, transactionId, updates) {
  const updateExpression = [];
  const expressionAttributeValues = {};
  const expressionAttributeNames = {};
  
  Object.keys(updates).forEach((key, index) => {
    updateExpression.push(`#attr${index} = :val${index}`);
    expressionAttributeNames[`#attr${index}`] = key;
    expressionAttributeValues[`:val${index}`] = updates[key];
  });
  
  const params = {
    TableName: CONFIG.DYNAMODB_TABLES.TRANSACTIONS,
    Key: {
      userId: userId,
      transactionId: transactionId
    },
    UpdateExpression: `SET ${updateExpression.join(', ')}`,
    ExpressionAttributeNames: expressionAttributeNames,
    ExpressionAttributeValues: expressionAttributeValues,
    ReturnValues: 'ALL_NEW'
  };
  
  const result = await dynamodb.update(params).promise();
  return result.Attributes;
}

async function deleteTransaction(userId, transactionId) {
  const params = {
    TableName: CONFIG.DYNAMODB_TABLES.TRANSACTIONS,
    Key: {
      userId: userId,
      transactionId: transactionId
    }
  };
  
  return dynamodb.delete(params).promise();
}

// ============================================
// BACKUP OPERATIONS
// ============================================

async function createBackup(userId) {
  try {
    // Get all user data
    const user = await getUser(userId);
    const transactions = await getUserTransactions(userId, 1000);
    
    const backupData = {
      user: user,
      transactions: transactions,
      timestamp: new Date().toISOString(),
      version: '1.0'
    };
    
    const key = `users/${userId}/backup-${Date.now()}.json`;
    
    await s3.putObject({
      Bucket: CONFIG.S3_BUCKET,
      Key: key,
      Body: JSON.stringify(backupData),
      ContentType: 'application/json',
      ServerSideEncryption: 'AES256',
      Metadata: {
        userId: userId,
        backupDate: new Date().toISOString()
      }
    }).promise();
    
    console.log(`Backup created for user ${userId}`);
    return { success: true, key: key };
  } catch (error) {
    console.error('Backup failed:', error);
    throw error;
  }
}

async function listBackups(userId) {
  const params = {
    Bucket: CONFIG.S3_BUCKET,
    Prefix: `users/${userId}/`
  };
  
  const result = await s3.listObjectsV2(params).promise();
  
  return result.Contents.map(item => ({
    key: item.Key,
    size: item.Size,
    lastModified: item.LastModified
  })).sort((a, b) => b.lastModified - a.lastModified);
}

async function restoreBackup(userId, backupKey = null) {
  try {
    let key = backupKey;
    
    // If no specific backup specified, get the most recent one
    if (!key) {
      const backups = await listBackups(userId);
      if (backups.length === 0) {
        throw new Error('No backups found for user');
      }
      key = backups[0].key;
    }
    
    const params = {
      Bucket: CONFIG.S3_BUCKET,
      Key: key
    };
    
    const data = await s3.getObject(params).promise();
    const backupData = JSON.parse(data.Body.toString());
    
    // Restore user data
    if (backupData.user) {
      await dynamodb.put({
        TableName: CONFIG.DYNAMODB_TABLES.USERS,
        Item: backupData.user
      }).promise();
    }
    
    // Restore transactions
    if (backupData.transactions && backupData.transactions.length > 0) {
      // Batch write transactions (25 at a time - DynamoDB limit)
      const chunks = [];
      for (let i = 0; i < backupData.transactions.length; i += 25) {
        chunks.push(backupData.transactions.slice(i, i + 25));
      }
      
      for (const chunk of chunks) {
        const batchParams = {
          RequestItems: {
            [CONFIG.DYNAMODB_TABLES.TRANSACTIONS]: chunk.map(txn => ({
              PutRequest: { Item: txn }
            }))
          }
        };
        await dynamodb.batchWrite(batchParams).promise();
      }
    }
    
    console.log(`Restored backup for user ${userId} from ${backupData.timestamp}`);
    return {
      success: true,
      restoredFrom: backupData.timestamp,
      transactionsRestored: backupData.transactions?.length || 0
    };
  } catch (error) {
    console.error('Restore failed:', error);
    throw error;
  }
}

// ============================================
// PUSH NOTIFICATION OPERATIONS
// ============================================

async function registerDeviceToken(userId, deviceToken, platform) {
  try {
    const platformArn = platform === 'ios' 
      ? CONFIG.SNS_PLATFORM_ARN.IOS 
      : CONFIG.SNS_PLATFORM_ARN.ANDROID;
    
    // Create platform endpoint
    const endpointResult = await sns.createPlatformEndpoint({
      PlatformApplicationArn: platformArn,
      Token: deviceToken,
      CustomUserData: userId
    }).promise();
    
    const endpointArn = endpointResult.EndpointArn;
    
    // Save endpoint ARN to user record
    const user = await getUser(userId);
    const deviceTokens = user.deviceTokens || [];
    
    // Remove old token if exists, add new one
    const updatedTokens = deviceTokens.filter(t => t.token !== deviceToken);
    updatedTokens.push({
      token: deviceToken,
      endpointArn: endpointArn,
      platform: platform,
      registeredAt: new Date().toISOString()
    });
    
    await updateUser(userId, { deviceTokens: updatedTokens });
    
    console.log(`Device registered for user ${userId}`);
    return { success: true, endpointArn: endpointArn };
  } catch (error) {
    console.error('Device registration failed:', error);
    throw error;
  }
}

async function sendNotification(userId, notification) {
  try {
    const user = await getUser(userId);
    
    if (!user.deviceTokens || user.deviceTokens.length === 0) {
      console.log('No device tokens found for user');
      return { success: false, reason: 'No devices registered' };
    }
    
    const results = [];
    
    for (const device of user.deviceTokens) {
      try {
        const message = {
          default: notification.body,
          GCM: JSON.stringify({
            notification: {
              title: notification.title,
              body: notification.body,
              sound: 'default'
            },
            data: notification.data || {}
          }),
          APNS: JSON.stringify({
            aps: {
              alert: {
                title: notification.title,
                body: notification.body
              },
              sound: 'default',
              badge: 1
            },
            customData: notification.data || {}
          })
        };
        
        await sns.publish({
          TargetArn: device.endpointArn,
          Message: JSON.stringify(message),
          MessageStructure: 'json'
        }).promise();
        
        results.push({ deviceToken: device.token, success: true });
      } catch (error) {
        console.error(`Failed to send to device ${device.token}:`, error);
        results.push({ deviceToken: device.token, success: false, error: error.message });
      }
    }
    
    return { success: true, results: results };
  } catch (error) {
    console.error('Send notification failed:', error);
    throw error;
  }
}

// ============================================
// EXPORTS
// ============================================

module.exports = {
  // User operations
  createUser,
  getUser,
  updateUser,
  
  // Transaction operations
  createTransaction,
  getUserTransactions,
  getTransaction,
  updateTransaction,
  deleteTransaction,
  
  // Backup operations
  createBackup,
  listBackups,
  restoreBackup,
  
  // Notification operations
  registerDeviceToken,
  sendNotification,
  
  // Configuration
  CONFIG
};