# الماسح الضوئي الذكي (CamScanner Offline RTL)

تطبيق مسح ضوئي احترافي ومستقل تماماً باللغة العربية (`RTL`)، يعمل **Offline 100%** بدون أي اتصال بالإنترنت أو سيرفرات خارجية أو حساب مستخدم.

---

## 🛠️ ملاحظات إعدادات Gradle وبيئة البناء (البند 1.5)

1. **`kotlin.incremental=false` (في `android/gradle.properties`)**:
   - **السبب**: إعداد خاص ببيئة Windows عندما يكون مجلد المشروع على قرص (`G:\cam_scanner`) ومجلد `Pub Cache` على قرص آخر (`C:\Users\...\AppData\Local\Pub\Cache`)؛ حيث يفشل محول المسارات النسبية في Kotlin (`RelocatableFileToPathConverter`) عند اختلاف حرف القرص. إذا نُقل المشروع لنفس القرص `C:\` يمكن حذف هذا السطر أو جعله `true`.
2. **`AGP 9.0.1` وBuilt-in Kotlin (في `android/settings.gradle.kts` و`android/app/build.gradle.kts`)**:
   - **السبب**: ضروري للتوافق مع قالب Flutter 3.41+ وGradle 9.1.0 حيث أصبحت واجهة `ApplicationExtension` والـ Built-in Kotlin مفعّلة افتراضياً بدلاً من `BaseAppModuleExtension` وبلوك `kotlinOptions` القديم.
3. **`JavaVersion.VERSION_21` (في `compileOptions` داخل `android/app/build.gradle.kts`)**:
   - **السبب**: حزمة JDK المثبتة على جهاز البناء هي Java 21، وبما أن مترجم Kotlin يستهدف تلقائياً إصدار الـ JDK الحالي (`21`)، فيجب مطابقة `sourceCompatibility` و`targetCompatibility` في Java مع `21` لمنع خطأ `Inconsistent JVM-target compatibility`.

---

## 📦 تغيير المعرّف النهائي للتطبيق (`applicationId` / Package)

تم ضبط المعرّف الحالي على القيمة القياسية: `com.yourname.docscanner`.
لتغييره إلى اسم شركتك أو نطاقك الخاص، عدّل المواضع الـ 3 التالية فقط:
1. `android/app/build.gradle.kts`: غيّر `namespace = "com.yourname.docscanner"` و`applicationId = "com.yourname.docscanner"`.
2. `android/app/proguard-rules.pro`: غيّر `-keep class com.yourname.docscanner.** { *; }`.
3. مجلد ملفات Kotlin في `android/app/src/main/kotlin/com/yourname/docscanner/`: غيّر مسار المجلد وسطر `package com.yourname.docscanner` في أول كل ملف.
*(ملاحظة: اسم قناة الاتصال `ismart/doc_scanner` مستقل عن اسم الحزمة ولا يحتاج لتغيير).*
