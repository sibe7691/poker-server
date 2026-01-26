# Poker App

Texas Hold'em Poker client built with Flutter.

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.10.7+)
- [Firebase CLI](https://firebase.google.com/docs/cli) (for deployment)

### Install Dependencies

```bash
flutter pub get
```

### Run Locally

```bash
# Run on web
flutter run -d chrome

# Run on iOS simulator
flutter run -d ios

# Run on Android emulator
flutter run -d android
```

## Deployment

The web app is hosted on Firebase Hosting.

### First-Time Setup

1. Install Firebase CLI:
   ```bash
   npm install -g firebase-tools
   ```

2. Login to Firebase:
   ```bash
   firebase login
   ```

### Deploy

Run the deploy script:

```bash
./scripts/deploy.sh
```

Or run the commands manually:

```bash
flutter build web --release
firebase deploy --only hosting
```

The app will be available at: https://seven-deuce-cc357.web.app

## Project Structure

```
lib/
├── core/           # Shared utilities, constants, themes
├── features/       # Feature modules
│   ├── auth/       # Login screen
│   ├── game/       # Poker table and game UI
│   └── lobby/      # Table selection
├── models/         # Data models
├── providers/      # Riverpod state management
├── services/       # API and WebSocket services
├── widgets/        # Reusable widgets
└── main.dart       # App entry point
```
