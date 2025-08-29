"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.placesAutocomplete = placesAutocomplete;
exports.placeDetails = placeDetails;
exports.parseLocationFromPlace = parseLocationFromPlace;
const dotenv_1 = __importDefault(require("dotenv"));
dotenv_1.default.config();
const API_KEY = process.env.GOOGLE_MAPS_API_KEY;
function ensureApiKey() {
    if (!API_KEY)
        throw new Error('Missing GOOGLE_MAPS_API_KEY');
}
function getFetch() {
    const f = global.fetch;
    if (!f)
        throw new Error('Global fetch not available. Use Node 18+');
    return f;
}
async function placesAutocomplete(input, opts = {}) {
    ensureApiKey();
    if (!input || !input.trim())
        return [];
    const fetchFn = getFetch();
    const params = new URLSearchParams({ input, key: API_KEY, types: 'geocode' });
    if (opts.language)
        params.set('language', opts.language);
    if (opts.sessionToken)
        params.set('sessiontoken', opts.sessionToken);
    const url = `https://maps.googleapis.com/maps/api/place/autocomplete/json?${params.toString()}`;
    const resp = await fetchFn(url);
    if (!resp.ok)
        throw new Error('Autocomplete HTTP ' + resp.status);
    const json = await resp.json();
    if (json.status !== 'OK' && json.status !== 'ZERO_RESULTS')
        throw new Error('Places Autocomplete error: ' + json.status);
    return (json.predictions || []).map((p) => ({
        description: p.description,
        placeId: p.place_id,
        matchedSubstrings: p.matched_substrings,
        types: p.types,
    }));
}
async function placeDetails(placeId, opts = {}) {
    ensureApiKey();
    if (!placeId)
        return null;
    const fetchFn = getFetch();
    const fields = ['place_id', 'geometry/location', 'address_component', 'name', 'formatted_address', 'types'];
    const params = new URLSearchParams({ place_id: placeId, key: API_KEY, fields: fields.join(',') });
    if (opts.language)
        params.set('language', opts.language);
    if (opts.sessionToken)
        params.set('sessiontoken', opts.sessionToken);
    const url = `https://maps.googleapis.com/maps/api/place/details/json?${params.toString()}`;
    const resp = await fetchFn(url);
    if (!resp.ok)
        throw new Error('Place details HTTP ' + resp.status);
    const json = await resp.json();
    if (json.status !== 'OK')
        throw new Error('Place Details error: ' + json.status);
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
function parseLocationFromPlace(details) {
    const get = (type) => details.addressComponents.find(c => c.types.includes(type))?.long_name || '';
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
//# sourceMappingURL=googlePlaces.js.map