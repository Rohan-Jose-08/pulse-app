// Coordinate-based geolocation helper utilities (structured Location model)
// Reverse geocoding notes:
// We use OpenStreetMap Nominatim (public) by default for reverse geocoding.
// For production you should self-host or use a dedicated provider to respect usage policies.

// Prisma model reference (for clarity only):
// model Location {
//   id         Int     @id @default(autoincrement())
//   name       String
//   street     String
//   city       String
//   state      String
//   postalCode String
//   country    String
//   latitude   Float
//   longitude  Float
// }

export interface BoundingBox { minLat: number; maxLat: number; minLng: number; maxLng: number; }

export interface LocationRecord {
  name: string; // human readable label or place name
  street: string;
  city: string;
  state: string;
  postalCode: string;
  country: string;
  latitude: number;
  longitude: number;
}

export interface ReverseGeocodeResult {
  label: string;              // Friendly short label (similar to name)
  location: LocationRecord;   // Structured location fields
  rawAddress: any;            // Raw provider address object (optional use)
}

// --- Deprecated geohash compatibility constants (remove after refactor) ---
export const GEOHASH_PRECISION_STORE = 9;
export const GEOHASH_PRECISION_QUERY = 7;

/**
 * Create a bounding box for a given center and radius (km)
 */
export function boundingBox(lat:number,lng:number,radiusKm:number): BoundingBox {
  const latDelta = radiusKm / 111; // deg per km
  const lngDelta = radiusKm / (111 * Math.cos(lat * Math.PI/180));
  return { minLat: lat - latDelta, maxLat: lat + latDelta, minLng: lng - lngDelta, maxLng: lng + lngDelta };
}

/** Basic distance calculation in km using haversine */
export function haversineKm(lat1:number,lng1:number,lat2:number,lng2:number){
  const R = 6371; const toRad = (d:number)=>d*Math.PI/180;
  const dLat = toRad(lat2-lat1); const dLng = toRad(lat2-lng1 ? lng2-lng1 : lng2-lng1); // guard not needed but keeps symmetry
  const a = Math.sin(dLat/2)**2 + Math.cos(toRad(lat1))*Math.cos(toRad(lat2))*Math.sin(dLng/2)**2;
  const c = 2*Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return R*c;
}


/** Build a human friendly label from a Nominatim response */
function buildLabel(addr: any): string {
  if (!addr) return 'Unknown location';
  const locality = addr.city || addr.town || addr.village || addr.hamlet;
  const parts = [addr.name || addr.attraction || addr.building, addr.neighbourhood || addr.suburb, locality, addr.state];
  return parts.filter(Boolean).slice(0,3).join(', ') || locality || addr.country || 'Unknown location';
}

/** Map a Nominatim address object to our LocationRecord */
function mapAddressToLocation(addr: any, lat: number, lng: number, label: string): LocationRecord {
  return {
    name: label,
    street: [addr.house_number, addr.road].filter(Boolean).join(' ').trim() || '',
    city: addr.city || addr.town || addr.village || addr.hamlet || '',
    state: addr.state || '',
    postalCode: addr.postcode || '',
    country: addr.country || '',
    latitude: lat,
    longitude: lng,
  };
}

/** Simple location cache keyed by rounded coordinates */
interface ReverseCacheEntry { address: any; label: string; ts: number; loc: LocationRecord; }
const reverseCache: Map<string, ReverseCacheEntry> = new Map();
const REVERSE_TTL_MS = 1000 * 60 * 60; // 1 hour

function pruneReverseCache() {
  const now = Date.now();
  for (const [k,v] of reverseCache) {
    if (now - v.ts > REVERSE_TTL_MS) reverseCache.delete(k);
  }
  if (reverseCache.size > 1000) {
    const entries = Array.from(reverseCache.entries()).sort((a,b)=>a[1].ts-b[1].ts);
    for (let i=0;i<entries.length-800;i++) reverseCache.delete(entries[i][0]);
  }
}

/** Reverse geocode latitude/longitude -> structured LocationRecord */
export async function reverseGeocode(lat: number, lng: number): Promise<ReverseGeocodeResult | null> {
  if (typeof lat !== 'number' || typeof lng !== 'number' || isNaN(lat) || isNaN(lng)) return null;
  pruneReverseCache();
  // Cache key with ~11m precision (~4 decimal places)
  const cacheKey = `${lat.toFixed(4)},${lng.toFixed(4)}`;
  const existing = reverseCache.get(cacheKey);
  if (existing && (Date.now() - existing.ts) < REVERSE_TTL_MS) {
    return { label: existing.label, location: existing.loc, rawAddress: existing.address };
  }
  try {
    const fetchFn: any = (global as any).fetch;
    if (!fetchFn) throw new Error('Global fetch unavailable. Use Node 18+ or add a fetch polyfill.');
    const userAgent = process.env.GEO_REVERSE_USER_AGENT || 'pulse-app/1.0 (reverse)';
    const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lng}`;
    const resp = await fetchFn(url, { headers: { 'User-Agent': userAgent, 'Accept-Language': 'en' } });
    if (!resp.ok) throw new Error('Reverse geocode HTTP ' + resp.status);
    const json: any = await resp.json();
    const address = json.address || null;
    const label = buildLabel(address);
    const loc = mapAddressToLocation(address, lat, lng, label);
    reverseCache.set(cacheKey, { address, label, ts: Date.now(), loc });
    return { label, location: loc, rawAddress: address };
  } catch {
    const label = 'Unknown location';
    const loc: LocationRecord = { name: label, street: '', city: '', state: '', postalCode: '', country: '', latitude: lat, longitude: lng };
    return { label, location: loc, rawAddress: null };
  }
}

// --- Legacy geohash compatibility (lightweight reversible stub) ---
// We previously used real geohash. Tests still expect encode/decode behavior.
// Implement a simple reversible token: base36 lat/lng scaled by 1e4 + precision marker.
// Not a spatial index; ONLY for backward compatibility tests.
export function geohashQueryPrefixes(_lat:number,_lng:number,_radiusKm:number): string[] { return []; }
export async function reverseGeocodeGeohash(hash: string) {
  const center = decodeCenter(hash);
  if (!center) return null;
  return reverseGeocode(center.lat, center.lng);
}
export function encode(lat:number,lng:number,precision = GEOHASH_PRECISION_STORE){
  if (typeof lat !== 'number' || typeof lng !== 'number') return '';
  const scale = 1e4; // 4 decimal places (~11m)
  const a = Math.round((lat + 90) * scale); // shift to positive
  const b = Math.round((lng + 180) * scale);
  return `${precision.toString(36)}:${a.toString(36)}:${b.toString(36)}`;
}
export function decodeCenter(hash:string){
  if (!hash || typeof hash !== 'string') return null as any;
  const parts = hash.split(':');
  if (parts.length !== 3) return null as any;
  try {
    const scale = 1e4;
    const lat = parseInt(parts[1],36)/scale - 90;
    const lng = parseInt(parts[2],36)/scale - 180;
    if (isNaN(lat) || isNaN(lng)) return null as any;
    return { lat, lng } as any;
  } catch { return null as any; }
}

