# CropEye Flutter App — Complete Edition

A pixel-perfect Flutter conversion of the CropEye Google AI Studio design.

## 📱 Screens Included

| Screen | Description |
|--------|-------------|
| **Onboarding** | Animated welcome with farm hero image, dual CTA buttons |
| **Registration** | Full multi-section form → Personal Info + Location + Crop Details |
| **Map Plot** | ArcGIS satellite map, tap to place 4 polygon corners, GPS centering |
| **Dashboard** | Live satellite map, 3D/2D toggle, NDVI overlay, compass nav, voice mic |
| **Soil Panel** | 6 nutrient bars with expandable details (PH, N, P, K, CEC, OC) |
| **Insights Panel** | Line chart (Nitrogen + Moisture), 4 insight cards with AI action plans |
| **Chat Panel** | AI assistant with chat bubbles |
| **Lands Panel** | All fields with alerts, rename/delete, add new plot |
| **Market Panel** | Live crop prices with trend indicators + AI prediction |
| **Scan Panel** | AI crop scanner with viewfinder UI + health analysis result |

## 🚀 Quick Start

```bash
# 1. Generate platform files
flutter create . --platforms=android,ios,web,windows

# 2. Install packages
flutter pub get

# 3. Run on Android (recommended)
flutter run

# 4. Run on Chrome
flutter run -d chrome
```

## 🌐 API Configuration

Base URL is set to your local server:
```dart
// lib/services/api_service.dart
static const String baseUrl = 'http://192.168.41.67:8005';
```

### Registration Endpoint
**POST** `/api/farmers/register/`

```json
{
  "registration": {
    "personal_info": {
      "first_name": "John",
      "last_name": "Doe",
      "username": "johndoe",
      "email_address": "john@example.com",
      "password": "securepassword123",
      "phone_number": "+919876543210",
      "village": "Village Name",
      "taluka": "Taluka Name",
      "district": "District Name",
      "state": "State Name"
    },
    "crop_details": {
      "crop_type": "Wheat",
      "crop_variety": "Kalyansona",
      "plantation_date": "2026-03-04",
      "irrigation_type": "Drip Irrigation"
    }
  }
}
```

## 📦 Package Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_map ^6.1.0` | Leaflet-style interactive map |
| `latlong2 ^0.9.0` | Lat/Lng coordinate types |
| `geolocator ^12.0.0` | GPS location & live tracking |
| `http ^1.2.0` | API calls |
| `intl ^0.19.0` | Date formatting |
| `fl_chart ^0.68.0` | Soil health trend chart |
| `image_picker ^1.1.2` | Photo library access for scan |
| `camera ^0.11.0+2` | Camera for crop scanning |
| `permission_handler ^11.3.1` | Runtime permissions |
| `speech_to_text ^6.6.2` | Voice input |

## 🎨 Design System

| Token | Value |
|-------|-------|
| Primary Green | `#2E7D32` |
| Accent Lime | `#A4C639` |
| Background | `#FAF9F6` |
| Secondary Brown | `#5D4037` |
| Dark BG | `#0A0A0A` |

## 📁 Project Structure

```
lib/
├── main.dart                          # App entry + navigation
├── constants/
│   ├── app_constants.dart             # Colors, theme, mock data, models
│   └── crop_data.dart                 # 100+ crops + varieties
├── services/
│   └── api_service.dart               # POST /api/farmers/register/
├── widgets/
│   └── common_widgets.dart            # Reusable UI components
└── screens/
    ├── onboarding_screen.dart         # Welcome screen
    ├── registration_screen.dart       # Full registration form
    ├── map_plot_screen.dart           # Satellite map polygon drawing
    ├── dashboard_screen.dart          # Main farm dashboard
    └── side_panels.dart               # All 6 slide-in panels
```

## ⚠️ Important Notes

- Make sure phone and API server are on the **same Wi-Fi network** (192.168.41.67)
- Android: `usesCleartextTraffic="true"` is set for HTTP (local network)
- iOS: Add NSAppTransportSecurity exception if needed for local HTTP
