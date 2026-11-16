CashSense: Request Test Refund button

This adds an iOS-only Request Test Refund button to Billing Staging Tests, using Apple's native StoreKit refund sheet. It does not change financial records or AWS resources.

Install
Stop the app without uninstalling or clearing its data. Extract the ZIP into Downloads, then run:
python3 "$HOME/Downloads/CashSense-Test-Refund-Button/install_test_refund.py" --project "/Users/siler/Projects/CashSenseFlutter"
cd /Users/siler/Projects/CashSenseFlutter
flutter pub get
(cd ios && pod install)
flutter analyze --no-pub

Build and upload a new staging TestFlight build using the same billing staging configuration as the previous successful purchase test. A full native rebuild is necessary; hot reload is insufficient. Flutter registers the local iOS plugin automatically; AppDelegate edits are not needed. pubspec.lock and Podfile.lock will update on the Mac; these files are not overwritten by the package. Keep the existing build number/version management process.

Test
1. Install the new staging build over the current app.
2. Sign into the SAME CashSense account and use the SAME Apple testing account as the original test purchase.
3. Open Billing Staging Tests > Request Test Refund.
4. Select the desired transaction, using product ID, purchase date and transaction ID. History is newest first.
5. Choose a refund reason in Apple's sheet and submit. To test an approved refund, select a normal reason (do not use Other with DECLINE).
6. The app reports submitted, cancelled or an error. Submitted means a request was sent, not proof of AWS processing or a completed refund.
7. Refresh Staging Membership after Apple's sandbox REFUND notification reaches AWS. Premium should become false if no other valid subscription, Lifetime entitlement or override remains.
8. Test Restore Purchases afterward. A refunded transaction must not reactivate Premium. Capture the result and membership status.

Restrictions
- Button is shown only on iOS staging builds. Android is unchanged.
- The native bridge requires iOS 16 or later to verify StoreKit's signed transaction environment. iOS 15 receives an unsupported message.
- Only StoreKit-verified sandbox transactions for the three CashSense product IDs are eligible. Production and Xcode-local transactions are excluded.
- The transaction's appAccountToken must match the authenticated CashSense account ID. Purchases missing that token are refused instead of guessing ownership; make a fresh test purchase with the current account if necessary.
- The system sheet remains responsible for eligibility and handling duplicate refund requests.
- The native bridge revalidates the selected transaction immediately before opening the sheet.
- The app does not mark Premium refunded locally or modify AWS directly. Apple's sandbox notifications and the existing AWS implementation determine the eventual result.
- Settings > Developer is not needed to open this in-app refund sheet for an eligible sandbox transaction.

Validation
Five Python installer checks and source screening passed. The packaging environment has no Flutter, Dart, Swift, Ruby or Xcode. Dependency resolution, CocoaPods installation, Swift compilation, Flutter analysis, native sheet presentation and AWS refund handling have NOT been tested here. Paste the Mac check output before proceeding with the new TestFlight build.

Apple references
https://developer.apple.com/documentation/storekit/testing-refund-requests
https://developer.apple.com/documentation/storekit/transaction/beginrefundrequest(in:)-9k0pj
https://developer.apple.com/documentation/storekit/transaction/environment
