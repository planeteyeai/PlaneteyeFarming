// ═══════════════════════════════════════════════════════════════════════════
//  APP STRINGS — full UI translation table
//  Supported: English (en), Hindi (hi), Marathi (mr), Kannada (kn)
//
//  Usage:
//    final t = AppStrings.of(context);   // reads current locale from context
//    Text(t.myLands)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class AppStrings {
  final String languageCode;
  const AppStrings(this.languageCode);

  // Factory that reads the current app locale from context
  static AppStrings of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return AppStrings(code);
  }

  String _t(String en, String hi, String mr, String kn) {
    switch (languageCode) {
      case 'hi': return hi;
      case 'mr': return mr;
      case 'kn': return kn;
      default:   return en;
    }
  }

  // ── Navigation / General ──────────────────────────────────────────────
  String get activeField     => _t('ACTIVE FIELD',     'सक्रिय खेत',       'सक्रिय शेत',      'ಸಕ್ರಿಯ ಜಮೀನು');
  String get myField         => _t('MY FIELD',         'मेरा खेत',          'माझे शेत',        'ನನ್ನ ಹೊಲ');
  String get myLands         => _t('My Lands',         'मेरी भूमि',         'माझ्या जमिनी',    'ನನ್ನ ಜಮೀನುಗಳು');
  String get addPlot         => _t('Add Plot',         'प्लॉट जोड़ें',      'प्लॉट जोडा',      'ಪ್ಲಾಟ್ ಸೇರಿಸಿ');
  String get newPlot         => _t('New Plot',         'नया प्लॉट',         'नवीन प्लॉट',      'ಹೊಸ ಪ್ಲಾಟ್');
  String get settings        => _t('SETTINGS',         'सेटिंग्स',          'सेटिंग्ज',        'ಸೆಟ್ಟಿಂಗ್‌ಗಳು');
  String get language        => _t('Language',         'भाषा',              'भाषा',             'ಭಾಷೆ');
  String get signOut         => _t('Sign Out',         'साइन आउट',          'साइन आउट',        'ಸೈನ್ ಔಟ್');
  String get back            => _t('Back',             'वापस',              'मागे',             'ಹಿಂದೆ');
  String get loading         => _t('Loading...',       'लोड हो रहा है...',  'लोड होत आहे...', 'ಲೋಡ್ ಆಗುತ್ತಿದೆ...');
  String get locating        => _t('Locating...',      'स्थान खोजा जा रहा है...', 'स्थान शोधत आहे...', 'ಸ್ಥಳ ಹುಡುಕಲಾಗುತ್ತಿದೆ...');

  // ── Plot / Farm ───────────────────────────────────────────────────────
  String get plotName        => _t('Plot Name',        'प्लॉट का नाम',     'प्लॉटचे नाव',     'ಪ್ಲಾಟ್ ಹೆಸರು');
  String get cropType        => _t('Crop Type',        'फसल का प्रकार',    'पिकाचा प्रकार',   'ಬೆಳೆ ವಿಧ');
  String get cropVariety     => _t('Crop Variety',     'फसल की किस्म',     'पिकाची जात',      'ಬೆಳೆ ತಳಿ');
  String get plantationDate  => _t('Plantation Date',  'रोपण तिथि',        'लागवडीची तारीख',  'ನಾಟಿ ದಿನಾಂಕ');
  String get irrigation      => _t('Irrigation',       'सिंचाई',            'सिंचन',            'ನೀರಾವರಿ');
  String get drawPlotOnMap   => _t('Draw Plot on Map', 'नक्शे पर प्लॉट बनाएं', 'नकाशावर प्लॉट काढा', 'ನಕ್ಷೆಯಲ್ಲಿ ಪ್ಲಾಟ್ ಚಿತ್ರಿಸಿ');
  String get confirmPlot     => _t('Confirm Plot',     'प्लॉट की पुष्टि करें', 'प्लॉट नक्की करा', 'ಪ್ಲಾಟ್ ದೃಢಪಡಿಸಿ');
  String get register        => _t('Register',         'पंजीकरण करें',     'नोंदणी करा',       'ನೋಂದಣಿ ಮಾಡಿ');
  String get login           => _t('Login',            'लॉगिन',             'लॉगिन',            'ಲಾಗಿನ್');

  // ── Dashboard labels ─────────────────────────────────────────────────
  String get soil            => _t('SOIL',    'मिट्टी',   'माती',   'ಮಣ್ಣು');
  String get water           => _t('WATER',   'पानी',     'पाणी',   'ನೀರು');
  String get pests           => _t('PESTS',   'कीट',      'कीड',    'ಕೀಟಗಳು');
  String get growth          => _t('GROWTH',  'विकास',    'वाढ',    'ಬೆಳವಣಿಗೆ');
  String get farmStatus      => _t('FARM STATUS', 'खेत की स्थिति', 'शेताची स्थिती', 'ಫಾರ್ಮ್ ಸ್ಥಿತಿ');
  String get insights        => _t('INSIGHTS', 'अंतर्दृष्टि', 'अंतर्दृष्टी', 'ಒಳನೋಟ');
  String get aiHelp          => _t('AI HELP',  'AI सहायता', 'AI मदत', 'AI ಸಹಾಯ');
  String get farmBoard       => _t('FARM BOARD', 'फार्म बोर्ड', 'फार्म बोर्ड', 'ಫಾರ್ಮ್ ಬೋರ್ಡ್');
  String get aiScan          => _t('AI SCAN',   'AI स्कैन',  'AI स्कॅन', 'AI ಸ್ಕ್ಯಾನ್');
  String get assist          => _t('ASSIST',    'सहायक',    'सहाय्यक',  'ಸಹಾಯಕ');
  String get aiCam           => _t('AI CAM',    'AI कैमरा', 'AI कॅमेरा', 'AI ಕ್ಯಾಮ');

  // ── Weather ───────────────────────────────────────────────────────────
  String get feelsLike       => _t('Feels Like',  'महसूस होता है', 'वाटते',      'ಅನಿಸಿಕೆ');
  String get humidity        => _t('Humidity',    'नमी',           'आर्द्रता',   'ಆರ್ದ್ರತೆ');
  String get wind            => _t('Wind',        'हवा',           'वारा',       'ಗಾಳಿ');
  String get direction       => _t('Direction',   'दिशा',          'दिशा',       'ದಿಕ್ಕು');
  String get cloudCover      => _t('Cloud Cover', 'बादल आवरण',    'ढगाळपणा',   'ಮೋಡ ಮುಸುಕು');
  String get rain1h          => _t('Rain 1h',     'बारिश 1घं',    'पाऊस 1तास', 'ಮಳೆ 1ಗಂ');
  String get time            => _t('Time',        'समय',           'वेळ',        'ಸಮಯ');
  String get daytime         => _t('Daytime',     'दिन का समय',   'दिवसा',      'ಹಗಲು');
  String get night           => _t('Night',       'रात',           'रात्री',     'ರಾತ್ರಿ');
  String get checkField      => _t('Check field', 'खेत जांचें',   'शेत तपासा',  'ಹೊಲ ಪರೀಕ್ಷಿಸಿ');
  String get notNeeded       => _t('Not needed',  'आवश्यक नहीं',  'आवश्यक नाही', 'ಅಗತ್ಯವಿಲ್ಲ');
  String get irrigationLabel => _t('Irrigation',  'सिंचाई',        'सिंचन',      'ನೀರಾವರಿ');

  // ── Search / Map ─────────────────────────────────────────────────────
  String get searchHint      => _t('Search village, city, district...', 'गांव, शहर, जिला खोजें...', 'गाव, शहर, जिल्हा शोधा...', 'ಗ್ರಾಮ, ನಗರ, ಜಿಲ್ಲೆ ಹುಡುಕಿ...');
  String get useMyLocation   => _t('Use My Current Location', 'मेरी वर्तमान स्थिति उपयोग करें', 'माझे सध्याचे स्थान वापरा', 'ನನ್ನ ಪ್ರಸ್ತುತ ಸ್ಥಳ ಬಳಸಿ');
  String get navigateToGps   => _t('Navigate map to your GPS position', 'GPS स्थिति पर नेविगेट करें', 'GPS स्थानावर जा', 'GPS ಸ್ಥಾನಕ್ಕೆ ಹೋಗಿ');
  String get drawYourPlot    => _t('Draw Your Plot', 'अपना प्लॉट बनाएं', 'तुमचा प्लॉट काढा', 'ನಿಮ್ಮ ಪ್ಲಾಟ್ ಚಿತ್ರಿಸಿ');

  // ── Profile ───────────────────────────────────────────────────────────
  String get plots           => _t('Plots',  'प्लॉट',  'प्लॉट',  'ಪ್ಲಾಟ್‌ಗಳು');
  String get status          => _t('Status', 'स्थिति', 'स्थिती', 'ಸ್ಥಿತಿ');
  String get active          => _t('Active', 'सक्रिय', 'सक्रिय', 'ಸಕ್ರಿಯ');
  String get app             => _t('App',    'ऐप',     'अ‍ॅप',    'ಆ್ಯಪ್');

  // ── Registration ─────────────────────────────────────────────────────
  String get firstName       => _t('First Name',     'पहला नाम',       'पहिले नाव',      'ಮೊದಲ ಹೆಸರು');
  String get lastName        => _t('Last Name',      'अंतिम नाम',      'आडनाव',           'ಕೊನೆಯ ಹೆಸರು');
  String get username        => _t('Username',       'उपयोगकर्ता नाम', 'वापरकर्ता नाव',  'ಬಳಕೆದಾರ ಹೆಸರು');
  String get email           => _t('Email',          'ईमेल',            'ईमेल',            'ಇಮೇಲ್');
  String get password        => _t('Password',       'पासवर्ड',         'पासवर्ड',         'ಪಾಸ್‌ವರ್ಡ್');
  String get phoneNumber     => _t('Phone Number',   'फोन नंबर',        'फोन नंबर',        'ಫೋನ್ ನಂಬರ್');
  String get village         => _t('Village',        'गांव',            'गाव',             'ಗ್ರಾಮ');
  String get taluka          => _t('Taluka',         'तालुका',          'तालुका',          'ತಾಲೂಕ');
  String get district        => _t('District',       'जिला',            'जिल्हा',          'ಜಿಲ್ಲೆ');
  String get state           => _t('State',          'राज्य',           'राज्य',           'ರಾಜ್ಯ');
}
