import Foundation

/// Bilingual (English / Arabic) copy for Analog Anchor iOS.
///
/// Phase 2 uses the same key terminology as the Android app. A full
/// Localizable.strings set is deferred; this lightweight table keeps the
/// foundation runnable and mirrors the Android English/Arabic switch.
enum L10n {
    static func text(_ key: Key, isEnglish: Bool) -> String {
        isEnglish ? key.english : key.arabic
    }

    enum Key {
        case appName, tagline
        case tabDashboard, tabAnchor, tabMosque, tabLedger, tabSettings
        case dashboardTitle, dayGuardStatus
        case reserveBalance, weeklyCeiling
        case paperRitual, retreat, lastFajr, weeklyMosquePrayers
        case softLanding, dhuhr, asr, maghrib, isha, fajr
        case anchorRitual, startRitual
        case protectedApps, dailyLimit
        case emergencyBypass, coolingWindow
        case protocolTitle, survivalTitle, accountabilityTitle
        case settings, general, appearance, features, dataManagement, about, developer
        case onboardWelcome, onboardBody, onboardContinue, onboardBegin
        case language, arabic, english

        var english: String {
            switch self {
            case .appName: return "Analog Anchor"
            case .tagline: return "Digital discipline, anchored to the physical world"
            case .tabDashboard: return "Dashboard"
            case .tabAnchor: return "Anchor"
            case .tabMosque: return "Mosque"
            case .tabLedger: return "Ledger"
            case .tabSettings: return "Settings"
            case .dashboardTitle: return "Today"
            case .dayGuardStatus: return "DAY GUARD"
            case .reserveBalance: return "RESERVE BALANCE"
            case .weeklyCeiling: return "Weekly Ceiling"
            case .paperRitual: return "PAPER RITUAL"
            case .retreat: return "RETREAT"
            case .lastFajr: return "LAST FAJR"
            case .weeklyMosquePrayers: return "WEEKLY MOSQUE PRAYERS"
            case .softLanding: return "Soft Landing"
            case .dhuhr: return "Dhuhr"
            case .asr: return "Asr"
            case .maghrib: return "Maghrib"
            case .isha: return "Isha"
            case .fajr: return "Fajr"
            case .anchorRitual: return "Thinking on Paper"
            case .startRitual: return "Start Ritual"
            case .protectedApps: return "Protected Apps"
            case .dailyLimit: return "Daily Limit"
            case .emergencyBypass: return "Emergency Bypass"
            case .coolingWindow: return "60-Minute Cooling Window"
            case .protocolTitle: return "Protocol"
            case .survivalTitle: return "Survival Kit"
            case .accountabilityTitle: return "Accountability"
            case .settings: return "Settings"
            case .general: return "General"
            case .appearance: return "Appearance"
            case .features: return "Features"
            case .dataManagement: return "Data Management"
            case .about: return "About"
            case .developer: return "Developer"
            case .onboardWelcome: return "Welcome to Analog Anchor"
            case .onboardBody: return "Anchor your focus to the physical world. This foundation keeps your rituals, prayer times and ledger intact — Screen Time protections arrive next."
            case .onboardContinue: return "Continue"
            case .onboardBegin: return "Begin"
            case .language: return "Language"
            case .arabic: return "العربية"
            case .english: return "English"
            }
        }

        var arabic: String {
            switch self {
            case .appName: return "المرساة الرقمية"
            case .tagline: return "انضباط رقمي مرتبط بالعالم الحقيقي"
            case .tabDashboard: return "الرئيسية"
            case .tabAnchor: return "المرساة"
            case .tabMosque: return "المسجد"
            case .tabLedger: return "السجل"
            case .tabSettings: return "الإعدادات"
            case .dashboardTitle: return "اليوم"
            case .dayGuardStatus: return "الحماية اليومية"
            case .reserveBalance: return "رصيد الاحتياط"
            case .weeklyCeiling: return "الحد الأسبوعي"
            case .paperRitual: return "التدبر اليومي"
            case .retreat: return "خلوة المغرب"
            case .lastFajr: return "الفجر"
            case .weeklyMosquePrayers: return "صلوات المسجد الأسبوعية"
            case .softLanding: return "الهبوط الناعم"
            case .dhuhr: return "الظهر"
            case .asr: return "العصر"
            case .maghrib: return "المغرب"
            case .isha: return "العشاء"
            case .fajr: return "الفجر"
            case .anchorRitual: return "التدبر اليومي"
            case .startRitual: return "ابدأ الطقس"
            case .protectedApps: return "التطبيقات المحمية"
            case .dailyLimit: return "الحد اليومي"
            case .emergencyBypass: return "التجاوز الطارئ"
            case .coolingWindow: return "نافذة التبريد ٦٠ دقيقة"
            case .protocolTitle: return "البروتوكول"
            case .survivalTitle: return "عدة النجاة"
            case .accountabilityTitle: return "المساءلة"
            case .settings: return "الإعدادات"
            case .general: return "عام"
            case .appearance: return "المظهر"
            case .features: return "الميزات"
            case .dataManagement: return "إدارة البيانات"
            case .about: return "حول"
            case .developer: return "المطور"
            case .onboardWelcome: return "مرحبًا بك في المرساة الرقمية"
            case .onboardBody: return "ثبّت تركيزك في العالم الحقيقي. تُبقي هذه الأساسيات طقوسك وأوقات صلاتك وسجلك سليمة — وتأتي حماية وقت الشاشة لاحقًا."
            case .onboardContinue: return "متابعة"
            case .onboardBegin: return "ابدأ"
            case .language: return "اللغة"
            case .arabic: return "العربية"
            case .english: return "English"
            }
        }
    }
}
