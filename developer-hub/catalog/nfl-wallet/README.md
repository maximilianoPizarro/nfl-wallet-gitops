# Stadium Wallet – Backstage Catalog

Backstage/Developer Hub catalog entities for Stadium Wallet. Used by [connectivity-link](https://gitlab.com/maximilianoPizarro/connectivity-link) Developer Hub.

**Source:** [connectivity-link/developer-hub/catalog/nfl-wallet](https://gitlab.com/maximilianoPizarro/connectivity-link/-/tree/main/developer-hub/catalog/nfl-wallet)

## Contents

| Entity | Kind | Description |
|--------|------|-------------|
| nfl-wallet | Domain | Stadium Wallet domain |
| nfl-wallet-system | System | Dev/test/prod application system |
| nfl-wallet-frontend | Component | React webapp |
| nfl-wallet-dev, -test, -prod | Component | Environment components |
| nfl-wallet-api-customers | API | Customers API (OpenAPI) |
| nfl-wallet-api-bills | API | Bills wallet API |
| nfl-wallet-api-raiders | API | Raiders wallet API |
| nfl-wallet-api-espn | API | ESPN scoreboard API |

## Cluster domain

The catalog uses east domain `cluster-64k4b.64k4b.sandbox5146.opentlc.com` in URLs. West: `cluster-7rt9h.7rt9h.sandbox1900.opentlc.com`. Update `servers` URLs and `backstage.io/view-url` annotations if your cluster domains differ.
