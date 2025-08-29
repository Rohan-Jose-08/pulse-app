// Deprecated script: geohash fields removed from schema. Keeping file as no-op to avoid build errors.
// Original functionality backfilled geohash columns which no longer exist.
// Safe to delete this file. Exporting empty main for compatibility if referenced in npm scripts.

export async function main() {
  console.log('backfill_geohash.ts: deprecated – no action performed');
}

if (require.main === module) {
  main().catch(e => { console.error(e); process.exit(1); });
}
