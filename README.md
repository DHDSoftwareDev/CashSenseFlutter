CashSense automatic account transition update

Behavior
- Signing out keeps the user's local records and opens the sign-in screen.
- Signing into the same account opens its saved local profile automatically.
- Another account receives its own local profile.
- Free and Premium accounts both retain local records after sign-out.
- Existing backup/restore access checks are retained. Signing in does not automatically restore a cloud backup.
- Authentication changes drain pending database, backup, restore, billing and push work; close Hive; rebuild providers and routes; and clear widgets before opening another profile.
- Delayed operations from a previous screen/session are rejected.
- The normal account-change restart screen is removed. Failed transitions keep records and show a retry action.
- Original shared-database files are never deleted or automatically assigned to an unverified owner. An uninitialized profile may still need the one-time ownership choice. Existing profiles do not repeat that choice.

Install
Stop the simulator app without uninstalling it or clearing its data. Extract this ZIP, then run:

python3 "$HOME/Downloads/CashSense-Account-Transition-Fix/install_account_transition.py" --project "/Users/siler/Projects/CashSenseFlutter"

The installer checks every input hash before editing, verifies installed bytes, backs up changed source outside the project and refuses files modified since the reviewed upload. Repeating installation is safe. It does not modify device data or AWS.

Verify on the Mac
cd /Users/siler/Projects/CashSenseFlutter
flutter analyze --no-pub
dart run checks/account_transition_check.dart
dart run checks/account_storage_check.dart
dart run checks/backup_payload_check.dart

The last two checks are from the previously installed packages; this ZIP does not replace them. Run a full simulator restart after installing this source once (not hot reload). Subsequent sign-ins/sign-outs should not require closing the app.

Simulator acceptance
1. In account A, create a clearly identified test transaction and note its amount and balance.
2. Sign out. The sign-in screen should open automatically.
3. Sign into A. The transaction and balance should return without closing the app.
4. Sign out and sign into B. A's transaction and other financial records must be absent.
5. Create a different transaction in B. Sign out/in to B and verify it returns.
6. Switch back to A and verify B's transaction is absent and A's amount/balance are unchanged.
7. Repeat with an incorrect password. The sign-in screen must remain usable.
8. Check widgets during sign-out and account switching for previous-account records.
9. Test a local backup/restore with disposable records separately. Cloud upload/download, cross-device restoration, and store billing need their own end-to-end tests.

Validation limits
The packaging environment has neither Flutter nor Dart installed. Flutter analysis, the Dart coordinator checks and the Hive/Cognito simulator acceptance tests have NOT been executed here. Python installer checks and source delimiter screening do not establish runtime correctness. Keep this build on the simulator until the Mac checks and account-switching acceptance test pass.
