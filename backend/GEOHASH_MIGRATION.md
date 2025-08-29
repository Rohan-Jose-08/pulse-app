# Geohash-Only Location Migration

This project migrated from storing raw latitude/longitude columns to geohash-only for privacy & simpler indexing.

## Summary
- Dropped columns: `Pulse.latitude`, `Pulse.longitude`, `User.locationLatitude`, `User.locationLongitude`, `User.locationAccuracy`.
- Added / standardized use of `Pulse.geohash` and `User.locationGeohash`.
- Nearby search now decodes geohash center to compute distance (haversine) for refinement.
- Frontend stopped sending `latitude` / `longitude` in create/update pulse APIs.

## Migration Steps (repeatable)
1. BEFORE applying schema migration run backfill script while old columns still exist:
   ```bash
   npx ts-node src/scripts/backfill_geohash.ts
   ```
2. Apply migration:
   ```bash
   npx prisma migrate dev --name geohash_only
   npx prisma generate
   ```
3. Rebuild & restart backend.
4. Verify: run health + nearby endpoints.
5. Remove any stale code referencing removed columns.

## Testing
Run unit tests (includes geolocation tests):
```bash
npm test
```

## Utility Endpoint
`GET /api/geohash/decode?hash=xxxxx` returns approximate center lat/lng for a hash (dev diagnostics, not for production exposure without auth).

## Future Ideas
- Add multi-precision geohash storage (coarse + fine) for faster broad queries.
- Bucketization or clustering for high-density areas.
- Optional encrypted geohash segments for privacy.

