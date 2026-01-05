# Pulse App

Full-stack social/pulse app with a Node.js/Express + Prisma backend and a Flutter mobile/web client.

## Repo Layout
- `backend/` � Node.js API, Prisma schema, PostgreSQL database access.
- `pulse/` � Flutter client (Android, iOS, web), integrates with Firebase and the backend API.
- `backend/prisma/` � Prisma schema and migrations.
- `backend/ml-service/` � ML-related helpers (see ML docs if you use them).

## Prerequisites
- Node.js 18+ and npm.
- PostgreSQL database you can connect to.
- Flutter SDK (stable channel) and platform toolchains (Android Studio / Xcode) if building mobile.
- Firebase project credentials:
  - Backend: service account JSON at `backend/firebase-admin-key.json` (or update `backend/src/firebase.ts`).
  - Flutter: `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`.
- (Optional) Google Maps API key set in the Flutter platform manifests if you use maps.

## Backend Setup (`backend/`)
1) Install deps:
```bash
npm install
```

2) Configure environment: create `.env` with at least:
```
DATABASE_URL=postgresql://user:pass@host:5432/dbname
PORT=3000                # optional
```
Place your Firebase service account file at `backend/firebase-admin-key.json` or adjust the path in `src/firebase.ts`.

3) Database schema:
```bash
npx prisma migrate deploy   # or: npx prisma db push (for dev)
npx prisma generate
```

4) Seed test data (optional):
```bash
npm run seed:pulses
```

5) Run:
- Dev (TS + reload): `npm run dev`
- Prod build: `npm run build` then `npm start` (runs `dist/index.js`)

## Flutter App Setup (`pulse/`)
1) Install deps:
```bash
flutter pub get
```

2) Firebase config: add `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`.

3) Backend URL:
- Defaults to `http://localhost:3000` (web/desktop) or `http://192.168.1.10:3000` (Android device/LAN).
- Override at build/run with `--dart-define=BACKEND_BASE=http://YOUR_HOST:3000`.

4) Run:
```bash
flutter run
```
Web build: `flutter build web`
Android APK: `flutter build apk --release`
iOS (on macOS): `flutter build ios --release`

## Developing Full Stack
- Start backend: `npm run dev` (in `backend/`).
- Start Flutter client: `flutter run` (in `pulse/`), passing `--dart-define=BACKEND_BASE=...` if not on the same host.

## Testing
- Backend tests: `npm test`.
- Flutter: `flutter test` (add tests as needed).

## Notes
- Prisma binary targets include `native` and `darwin`; regenerate after changing the schema: `npx prisma generate`.
- Keep secrets out of version control; `.env` and Firebase keys should stay local or in your secret manager.
