**Route Migration Plan**

Local-first architecture means user finance records stay on-device. AWS keeps auth, premium backup/restore, device registration, and push scheduling.

**Keep**

- `GET /users/me`
- `POST /devices`
- `POST /devices/{deviceToken}`
- `DELETE /devices`
- `DELETE /devices/{deviceToken}`
- `GET /notification-schedules`
- `POST /notification-schedules`
- `DELETE /notification-schedules/{scheduleId}`
- `POST /backup/init`
- `POST /backup/complete`
- `GET /backup/latest`
- `POST /entitlements/refresh`
- `POST /apple/notifications`

**Legacy 410 Now**

- `GET /accounts`
- `POST /accounts`
- `PUT /accounts/{accountId}`
- `DELETE /accounts/{accountId}`
- `GET /transactions`
- `POST /transactions`
- `PUT /transactions/{transactionId}`
- `DELETE /transactions/{transactionId}`
- `GET /bills`
- `POST /bills`
- `PUT /bills`
- `DELETE /bills`
- `GET /users/{userId}/bills`
- `POST /users/{userId}/bills`
- `PUT /users/{userId}/bills/{billId}`
- `DELETE /users/{userId}/bills/{billId}`
- `GET /lookups`
- `POST /lookups`
- `PUT /lookups`
- `DELETE /lookups`
- `POST /payments`
- `GET /payments`
- `POST /send-notification`

**Remove Next**

- Integration `6lt03af` -> `CashSense-Accounts`
- Integration `y2yi9zb` -> `CashSense-Transactions`
- Integration `nuv5um1` -> `CashSense-Bills`
- Integration `2xe39uk` -> `CashSense-Lookups`
- Integration `on5lybd` -> `CashSense-BillPayments`
- Integration `ilm4yml` -> `CashSense-SendNotification`
- Integration `4l6hz72` -> `CashSense-ScheduleBillReminder`

**Rollout**

1. Deploy the Lambda stubs so legacy routes return `410 LOCAL_FIRST_ONLY`.
2. Verify current mobile clients no longer depend on cloud CRUD.
3. Remove the legacy routes from API Gateway.
4. Remove the unused Lambda integrations.
5. Tighten IAM so remaining functions no longer need finance-table CRUD permissions.
