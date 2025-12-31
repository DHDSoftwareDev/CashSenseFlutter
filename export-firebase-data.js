// export-firebase-data.js
// Export all data from Firebase to JSON files

const admin = require('firebase-admin');
const fs = require('fs');

// Initialize Firebase Admin
// Download your service account key from Firebase Console:
// Project Settings → Service Accounts → Generate New Private Key
const serviceAccount = require('./firebase-service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function exportCollection(collectionName, outputFile) {
  console.log(`\n📥 Exporting ${collectionName}...`);
  
  try {
    const snapshot = await db.collection(collectionName).get();
    const data = [];
    
    snapshot.forEach(doc => {
      const docData = doc.data();
      
      // Convert Firestore Timestamps to ISO strings
      Object.keys(docData).forEach(key => {
        if (docData[key] && typeof docData[key].toDate === 'function') {
          docData[key] = docData[key].toDate().toISOString();
        }
      });
      
      data.push({
        id: doc.id,
        ...docData
      });
    });
    
    fs.writeFileSync(outputFile, JSON.stringify(data, null, 2));
    console.log(`✅ Exported ${data.length} documents to ${outputFile}`);
    
    return data.length;
  } catch (error) {
    console.error(`❌ Error exporting ${collectionName}:`, error.message);
    return 0;
  }
}

async function exportAllData() {
  console.log('🚀 Starting Firebase data export...\n');
  
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const exportDir = `firebase-export-${timestamp}`;
  
  // Create export directory
  if (!fs.existsSync(exportDir)) {
    fs.mkdirSync(exportDir);
  }
  
  const collections = {
    'users': 'users.json',
    'transactions': 'transactions.json',
    'categories': 'categories.json',
    'budgets': 'budgets.json',
    'settings': 'settings.json',
    // Add any other collections your app uses
  };
  
  let totalDocuments = 0;
  
  for (const [collection, filename] of Object.entries(collections)) {
    const count = await exportCollection(
      collection, 
      `${exportDir}/${filename}`
    );
    totalDocuments += count;
  }
  
  // Create a summary file
  const summary = {
    exportDate: new Date().toISOString(),
    totalCollections: Object.keys(collections).length,
    totalDocuments: totalDocuments,
    collections: collections
  };
  
  fs.writeFileSync(
    `${exportDir}/export-summary.json`,
    JSON.stringify(summary, null, 2)
  );
  
  console.log('\n' + '='.repeat(60));
  console.log('✅ Export Complete!');
  console.log('='.repeat(60));
  console.log(`\n📁 Export directory: ${exportDir}`);
  console.log(`📊 Total documents exported: ${totalDocuments}`);
  console.log('\n🚀 Next step: Run the import script to move data to AWS');
  console.log('\n');
  
  process.exit(0);
}

// Run the export
exportAllData().catch(error => {
  console.error('\n❌ Export failed:', error);
  process.exit(1);
});