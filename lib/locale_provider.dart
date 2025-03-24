import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thay đổi ngôn ngữ và Thông báo cho các widget khi ngôn ngữ thay đổi
/// Lưu preferences
class LocaleProvider with ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  LocaleProvider() {
    _loadLocale();
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale != locale) {
      _locale = locale;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('locale', locale.languageCode);
    }
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final localeCode = prefs.getString('locale') ?? 'en';
    _locale = Locale(localeCode);
    notifyListeners();
  }
}
