# Ethiopian Events

Android-first Flutter MVP for organizing weddings, cultural festivals, and community events in Ethiopia. Organizers create events and guest invitations; each guest receives a QR ticket; assigned gate staff verify tickets online at the entrance.

## Current status and limitations

This repository contains the initial Flutter/Firebase MVP implementation. Firebase credentials and platform configuration are intentionally not committed. The app is not production-ready until you configure Firebase, deploy rules/functions, assign roles, and test on real Android devices.

- Email/password registration and sign-in use Firebase Authentication. Registration sends an email verification message; the MVP currently does not block sign-in on the verified flag.
- Organizers can create, edit, and list events, invite guests, assign gate staff, and view guest/attendance status.
- Roles are provisioned by an administrator in Firestore; users cannot grant themselves roles.
- Ticket creation, staff assignment, and check-in are callable Cloud Functions. Raw credentials are generated securely in the app; only SHA-256 hashes are stored in Firestore.
- Check-in is online-only. There is no offline queue. Gate staff can search the event guest list by name or phone as a manual fallback.
- Guest ticket sharing currently shares QR payload text. A public deep-link landing page and automatic email/SMS delivery are not included.
- Amharic locale is declared as an extension point; the initial UI strings are English.
- The initial guest ticket QR is shown to the organizer immediately after creation. A guest-facing redemption page is not yet included.

## Prerequisites

- Flutter stable (Dart SDK included), Android Studio / Android SDK, and a physical Android phone or emulator.
- Node.js 20 and npm for Cloud Functions.
- Firebase project with Authentication (Email/Password), Cloud Firestore, and Cloud Functions enabled.
- Firebase CLI: `npm install -g firebase-tools`
- FlutterFire CLI: `dart pub global activate flutterfire_cli`

## Configure Firebase for Android

1. Create a Firebase project at https://console.firebase.google.com/.
2. Add an Android app using the exact application ID from `android/app/build.gradle` or `android/app/build.gradle.kts` after creating the Flutter platform scaffold. Use `com.example.ethiopian_events` unless you change the Flutter application ID.
3. From the repository root run:
   ```bash
   flutter create --platforms=android .
   flutter pub get
   flutterfire configure
   ```
   Select your Firebase project and Android app. This generates `lib/firebase_options.dart`; it is intentionally ignored by Git. Update `lib/main.dart` to initialize with `DefaultFirebaseOptions.currentPlatform` if your FlutterFire CLI version does not configure the default initialization automatically. Recommended initialization:
   ```dart
   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
   ```
4. In Firebase Console → Authentication → Sign-in method, enable Email/Password.
5. Create a Firestore database. Choose a region close to your users where available; keep the Functions region aligned with the database region if you customize it.
6. Enable billing/Blaze for deployed Cloud Functions if Firebase requires it for your project. Do not put service-account JSON files in this repository.

## Build and run

From the repository root:

```bash
flutter create --platforms=android .
flutter pub get
flutter analyze
flutter test
flutter run
```

The Android camera permission is required for scanning. Confirm `android/app/src/main/AndroidManifest.xml` includes:
```xml
<uses-permission android:name="android.permission.CAMERA" />
```
The `mobile_scanner` plugin normally provides the camera integration; verify the permission in the generated manifest and test permission denial on-device.

## Deploy Firestore rules and Cloud Functions

```bash
firebase login
firebase use --add
cd functions
npm install
npm test
cd ..
firebase deploy --only firestore:rules,functions
```

Cloud Functions use the default deployment region. If you change it, configure the Flutter callable client to use the same region.

## First organizer and gate staff setup

1. Register through the app using the organizer's email. Firebase Authentication creates the account and sends a verification email.
2. In Firebase Console → Authentication → Users, copy the organizer UID.
3. In Firestore, create `users/{ORGANIZER_UID}` with:
   ```json
   { "role": "organizer" }
   ```
4. Register the gate staff account through the app and copy its Firebase Auth UID.
5. Create `users/{GATE_STAFF_UID}` with:
   ```json
   { "role": "gateStaff" }
   ```
6. Open an event and tap **Staff**. Enter the gate staff user's Firebase Auth UID and assign them. The callable verifies the signed-in organizer owns the event and that the target account has `gateStaff` role. Never let clients write role documents directly.

## Data model

- `users/{uid}`: administrator-managed role: `organizer` or `gateStaff`.
- `events/{eventId}`: event details, `organizerUid`, and `attendanceCount`.
- `events/{eventId}/guests/{guestId}`: guest contact details, ticket hash, check-in state.
- `events/{eventId}/staff/{uid}`: event staff assignment.

## Security notes

- Firestore rules deny direct client writes to guest records and staff membership.
- Callable functions verify authenticated identity and event access. Check-in is committed in a Firestore transaction, so concurrent scans cannot check in a ticket twice.
- QR data contains only version, event ID, and opaque random credential; no guest name, phone, or email.
- For production, add App Check, rate limiting/abuse monitoring, audited role provisioning, and a dedicated guest ticket delivery/deep-link flow.

## Tests

```bash
flutter test
cd functions && npm test && npm run lint
```

Flutter commands require a locally installed Flutter SDK and generated Android platform folder. Firebase deployment requires your own authenticated Firebase project.
