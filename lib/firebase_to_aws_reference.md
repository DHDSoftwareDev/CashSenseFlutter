# Firebase to AWS Migration Reference

## Get User Data
```dart
// OLD Firebase:
final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
final userData = doc.data();

// NEW AWS:
final userData = await awsService.getUser(userId);
```

## Create Transaction
```dart
// OLD Firebase:
await FirebaseFirestore.instance.collection('transactions').add({
  'userId': userId,
  'amount': 50.00,
  'category': 'Food',
});

// NEW AWS:
await awsService.createTransaction(
  userId: userId,
  amount: 50.00,
  category: 'Food',
  type: 'expense',
);
```

## Get Transactions
```dart
// OLD Firebase with StreamBuilder:
StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance
      .collection('transactions')
      .where('userId', isEqualTo: userId)
      .snapshots(),
  builder: (context, snapshot) {
    // ...
  },
)

// NEW AWS with FutureBuilder and RefreshIndicator:
FutureBuilder<List<Map<String, dynamic>>>(
  future: awsService.getTransactions(userId),
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      return RefreshIndicator(
        onRefresh: () async {
          setState(() {}); // Triggers rebuild
        },
        child: ListView.builder(...),
      );
    }
    return CircularProgressIndicator();
  },
)
```

## Update Transaction
```dart
// OLD Firebase:
await FirebaseFirestore.instance
    .collection('transactions')
    .doc(transactionId)
    .update({'amount': 75.00});

// NEW AWS:
await awsService.updateTransaction(
  userId: userId,
  transactionId: transactionId,
  updates: {'amount': 75.00},
);
```

## Delete Transaction
```dart
// OLD Firebase:
await FirebaseFirestore.instance
    .collection('transactions')
    .doc(transactionId)
    .delete();

// NEW AWS:
await awsService.deleteTransaction(
  userId: userId,
  transactionId: transactionId,
);
```