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
