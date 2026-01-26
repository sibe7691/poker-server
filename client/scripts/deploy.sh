#!/bin/bash
set -e

echo "🔨 Building Flutter web app..."
flutter build web --release

echo "🚀 Deploying to Firebase Hosting..."
firebase deploy --only hosting

echo "✅ Deployment complete!"
echo "🌐 Your app is live at: https://seven-deuce-cc357.web.app"
