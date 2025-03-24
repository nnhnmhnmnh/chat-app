import 'dart:convert'; // Để làm việc với dữ liệu JSON (đọc, giải mã)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Để đọc file từ thư mục assets

/// Đọc các file JSON, quản lý các bản dịch, và lấy bản dịch dựa vào key
class AppLocalizations {
  final Locale locale; // Lưu trữ ngôn ngữ hiện tại

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
  _AppLocalizationsDelegate();

  late Map<String, String> _localizedStrings; // Map(ID, translate)

  Future<void> load() async {
    final jsonString = await rootBundle
        .loadString('assets/locales/${locale.languageCode}.json');
    final Map<String, dynamic> jsonMap = json.decode(jsonString);

    _localizedStrings = jsonMap.map((key, value) => MapEntry(key, value.toString()));
  }

  String translate(String key) {
    return _localizedStrings[key] ?? key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'vi'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
