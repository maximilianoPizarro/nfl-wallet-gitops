# NFL Wallet – Backstage Catalog

Backstage/Developer Hub catalog entities for NFL Stadium Wallet. Used by [connectivity-link](https://gitlab.com/maximilianoPizarro/connectivity-link) Developer Hub.

**Source:** [connectivity-link/developer-hub/catalog/nfl-wallet](https://gitlab.com/maximilianoPizarro/connectivity-link/-/tree/main/developer-hub/catalog/nfl-wallet)

## Contents

| Entity | Kind | Description |
|--------|------|-------------|
| nfl-wallet | Domain | NFL Stadium Wallet domain |
| nfl-wallet-system | System | Dev/test/prod application system |
| nfl-wallet-frontend | Component | React webapp |
| nfl-wallet-dev, -test, -prod | Component | Environment components |
| nfl-wallet-api-customers | API | Customers API (OpenAPI) |
| nfl-wallet-api-bills | API | Buffalo Bills wallet API |
| nfl-wallet-api-raiders | API | Las Vegas Raiders wallet API |
| nfl-wallet-api-espn | API | ESPN scoreboard API |

## Cluster domain

The catalog uses east domain `cluster-thmg4.thmg4.sandbox4076.opentlc.com` in URLs. West: `cluster-2tjvj.2tjvj.sandbox5367.opentlc.com`. Update `servers` URLs and `backstage.io/view-url` annotations if your cluster domains differ.
