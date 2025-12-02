#!/bin/bash

# Frontend Application Startup Script

echo "=== Starting Frontend Application ==="
echo ""

# Navigate to frontend directory
cd "$(dirname "$0")/FRONTEND" || exit 1

# Check if flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "Error: flutter command not found"
    echo "Please install Flutter SDK and configure environment variables"
    exit 1
fi

# Check dependencies
echo "Checking dependencies..."
flutter pub get

# Start application
echo ""
echo "Starting Flutter Application..."
echo "If you have multiple devices, please select one as prompted."
echo "Chrome (enter '1' or corresponding number) is recommended for quick preview."
echo ""
echo "Press 'q' or 'R' in the terminal to control the application"
echo ""

flutter run

