#!/bin/bash
# Auto-copy assets to app bundle after build
# Run this after building the project

APP_BUNDLE="/Users/dave/Library/Developer/Xcode/DerivedData/SGFPlayerClean-dmhbjjmytvwhytffvzwazruxcndm/Build/Products/Debug/SGFPlayerClean.app"
ASSETS_SOURCE="/Users/Dave/SGFPlayerClean/SGFPlayerClean/Assets"

if [ -d "$APP_BUNDLE" ]; then
    echo "Copying assets to app bundle..."
    cp "$ASSETS_SOURCE"/*.{png,jpg,mp3} "$APP_BUNDLE/Contents/Resources/" 2>/dev/null
    echo "✅ Assets copied successfully"
else
    echo "❌ App bundle not found at: $APP_BUNDLE"
fi
