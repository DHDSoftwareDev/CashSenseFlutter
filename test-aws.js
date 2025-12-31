// test-aws.js
require('dotenv').config();
const aws = require('./awsHelper');

async function runTests() {
  console.log('🧪 Testing AWS Integration...\n');
  
  try {
    // Test 1: Get a user
    console.log('Test 1: Getting users...');
    // Replace with one of your actual user IDs from the import
    const userId = 'YOUR_ACTUAL_USER_ID';
    const user = await aws.getUser(userId);
    console.log('✅ User found:', user ? user.email : 'No user');
    
    // Test 2: Get transactions
    console.log('\nTest 2: Getting transactions...');
    const transactions = await aws.getUserTransactions(userId);
    console.log('✅ Found', transactions.length, 'transactions');
    
    // Test 3: Create a test transaction
    console.log('\nTest 3: Creating test transaction...');
    const txnId = await aws.createTransaction(userId, {
      amount: 10.00,
      category: 'Test',
      description: 'AWS Migration Test',
      type: 'expense',
      date: new Date().toISOString()
    });
    console.log('✅ Transaction created:', txnId);
    
    // Test 4: Create backup
    console.log('\nTest 4: Creating backup...');
    await aws.createBackup(userId);
    console.log('✅ Backup created');
    
    // Test 5: List backups
    console.log('\nTest 5: Listing backups...');
    const backups = await aws.listBackups(userId);
    console.log('✅ Found', backups.length, 'backups');
    
    console.log('\n🎉 All tests passed!');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    console.error(error);
  }
}

runTests();