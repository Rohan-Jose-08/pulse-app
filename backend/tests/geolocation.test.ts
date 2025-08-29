import request from 'supertest';
import { app } from '../src/index';
import { encode, decodeCenter, haversineKm } from '../src/services/geolocation';

describe('Geolocation utilities', () => {
  test('encode/decodeCenter round trip approximate center', () => {
    const lat = 37.7749; const lng = -122.4194;
    const hash = encode(lat, lng);
    const center = decodeCenter(hash)!;
    expect(center).toBeTruthy();
    // Within ~0.01 deg (~1km) due to geohash precision
    expect(Math.abs(center.lat - lat)).toBeLessThan(0.02);
    expect(Math.abs(center.lng - lng)).toBeLessThan(0.02);
  });

  test('haversine distance roughly zero for identical points', () => {
    expect(haversineKm(10,20,10,20)).toBeLessThan(0.001);
  });
});

describe('Geohash decode endpoint', () => {
  test('returns center for valid hash', async () => {
    const hash = encode(40.7128, -74.0060, 7);
    const resp = await request(app).get('/api/geohash/decode').query({ hash });
    expect(resp.status).toBe(200);
    expect(resp.body.center).toBeDefined();
  });

  test('400 on missing hash', async () => {
    const resp = await request(app).get('/api/geohash/decode');
    expect(resp.status).toBe(400);
  });
});
