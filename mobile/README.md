# mobile

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## API base URL

By default the app calls the production API:

```sh
flutter run
```

To hit a local debug backend, pass `API_BASE_URL`:

```sh
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

Use `10.0.2.2` for the Android emulator. For a physical phone, use your
computer's LAN IP instead, for example:

```sh
flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8000/api/v1
```

## Sign in with Google

The app sends a Google ID token to `POST /auth/google`, which the backend
verifies. The only build-time value the app needs is the **Web** OAuth client ID
— client IDs are public, so there is no secret in the app. Use the Web client ID
(the same value as the backend's `GOOGLE_CLIENT_IDS`), NOT the Android client ID.

1. Copy the template and fill in your Web client ID:

   ```sh
   cp env.example.json env.json   # env.json is gitignored
   ```

2. Build/run with the config file so `GOOGLE_SERVER_CLIENT_ID` is read
   automatically:

   ```sh
   flutter run --dart-define-from-file=env.json
   flutter build apk --debug --dart-define-from-file=env.json
   ```

   Combine with other defines as needed, e.g. a local API:

   ```sh
   flutter run --dart-define-from-file=env.json --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
   ```

In Google Cloud Console you also need an **Android** OAuth client in the same
project, registered with package name `com.pervez.personalfinance.mobile` and
the signing-key SHA-1. The debug keystore SHA-1 (from
`cd android && ./gradlew signingReport`) authorizes debug APKs; add the release
keystore SHA-1 for release builds.
