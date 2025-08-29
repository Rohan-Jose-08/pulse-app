import dotenv from 'dotenv';
dotenv.config();

// Lightweight Google Places Autocomplete + Details wrapper
// Requires env GOOGLE_MAPS_API_KEY (Server key restricted to Places API & your backend IPs)

export interface PlaceAutocompletePrediction {
  description: string;
  placeId: string;
  matchedSubstrings?: { length: number; offset: number }[];
  types?: string[];
}

export interface PlaceDetailsAddressComponents {
  long_name: string; short_name: string; types: string[];
}

export interface PlaceDetailsResult {
  placeId: string;
  name: string;
  latitude: number;
  longitude: number;
  addressComponents: PlaceDetailsAddressComponents[];
  formattedAddress?: string;
  types?: string[];
}

export interface ParsedLocationFromPlaceDetails {
  name: string;
  street: string;
  city: string;
  state: string;
  postalCode: string;
  country: string;
  latitude: number;
  longitude: number;
}

const API_KEY = process.env.GOOGLE_MAPS_API_KEY;

function ensureApiKey() {
  if (!API_KEY) throw new Error('Missing GOOGLE_MAPS_API_KEY');
}

function getFetch(): typeof fetch {
  const f: any = (global as any).fetch;
  if (!f) throw new Error('Global fetch not available. Use Node 18+');
  return f;
}

export async function placesAutocomplete(input: string, opts: { sessionToken?: string; language?: string } = {}): Promise<PlaceAutocompletePrediction[]> {
  ensureApiKey();
  if (!input || !input.trim()) return [];
  const fetchFn = getFetch();
  const params = new URLSearchParams({ input, key: API_KEY!, types: 'geocode' });
  if (opts.language) params.set('language', opts.language);
  if (opts.sessionToken) params.set('sessiontoken', opts.sessionToken);
  const url = `https://maps.googleapis.com/maps/api/place/autocomplete/json?${params.toString()}`;
  const resp = await fetchFn(url);
  if (!resp.ok) throw new Error('Autocomplete HTTP ' + resp.status);
  const json = await resp.json();
  if (json.status !== 'OK' && json.status !== 'ZERO_RESULTS') throw new Error('Places Autocomplete error: ' + json.status);
  return (json.predictions || []).map((p: any) => ({
    description: p.description,
    placeId: p.place_id,
    matchedSubstrings: p.matched_substrings,
    types: p.types,
  }));
}

export async function placeDetails(placeId: string, opts: { sessionToken?: string; language?: string } = {}): Promise<PlaceDetailsResult | null> {
  ensureApiKey();
  if (!placeId) return null;
  const fetchFn = getFetch();
  const fields = ['place_id', 'geometry/location', 'address_component', 'name', 'formatted_address', 'types'];
  const params = new URLSearchParams({ place_id: placeId, key: API_KEY!, fields: fields.join(',') });
  if (opts.language) params.set('language', opts.language);
  if (opts.sessionToken) params.set('sessiontoken', opts.sessionToken);
  const url = `https://maps.googleapis.com/maps/api/place/details/json?${params.toString()}`;
  const resp = await fetchFn(url);
  if (!resp.ok) throw new Error('Place details HTTP ' + resp.status);
  const json = await resp.json();
  if (json.status !== 'OK') throw new Error('Place Details error: ' + json.status);
  const r = json.result;
  return {
    placeId: r.place_id,
    name: r.name,
    latitude: r.geometry?.location?.lat,
    longitude: r.geometry?.location?.lng,
    addressComponents: r.address_components || [],
    formattedAddress: r.formatted_address,
    types: r.types || []
  };
}

// Helper to map Google address_components to our Location model fields
export function parseLocationFromPlace(details: PlaceDetailsResult): ParsedLocationFromPlaceDetails {
  const get = (type: string) => details.addressComponents.find(c => c.types.includes(type))?.long_name || '';
  const streetNumber = get('street_number');
  const route = get('route');
  const city = get('locality') || get('postal_town') || get('sublocality') || get('administrative_area_level_2');
  const state = get('administrative_area_level_1');
  const postalCode = get('postal_code');
  const country = get('country');
  const street = [streetNumber, route].filter(Boolean).join(' ').trim();
  return {
    name: details.name || city || country || 'Unknown location',
    street,
    city,
    state,
    postalCode,
    country,
    latitude: details.latitude,
    longitude: details.longitude,
  };
}
