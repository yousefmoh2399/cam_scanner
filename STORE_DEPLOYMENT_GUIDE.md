# الدليل الشامل لرفع ونشر تطبيق "لقطة" (Laqta Scanner) على متجري Google Play و Apple App Store

هذا الدليل يوضح لك بالخطوات الدقيقة والأوامر التنفيذية كيفية تجهيز، وبناء، وتوقيع، ورفع التطبيق على متجري **جوجل بلاي (Google Play)** و **آبل ستور (Apple App Store)**، واجتياز مرحلة المراجعة (App Review) بدون أي رفض.

---

## 📋 الفهرس
1. [المتطلبات الأساسية والحسابات](#1-المتطلبات-الأساسية-والحسابات)
2. [الجزء الأول: النشر على Google Play Store](#2-الجزء-الأول-النشر-على-google-play-store)
   - [أ. إنشاء مفتاح التوقيع الرقمي (Upload Keystore)](#أ-إنشاء-مفتاح-التوقيع-الرقمي-upload-keystore)
   - [ب. إعداد ملف التوقيع key.properties](#ب-إعداد-ملف-التوقيع-keyproperties)
   - [ج. بناء حزمة التطبيق الرسمية (AAB)](#ج-بناء-حزمة-التطبيق-الرسمية-aab)
   - [د. خطوات Google Play Console واستبيان أمان البيانات](#د-خطوات-google-play-console-واستبيان-أمان-البيانات)
3. [الجزء الثاني: النشر على Apple App Store](#3-الجزء-الثاني-النشر-على-apple-app-store)
   - [أ. إعداد حساب المطور وتحديد المعرف (Bundle Identifier)](#أ-إعداد-حساب-المطور-وتحديد-المعرف-bundle-identifier)
   - [ب. تجهيز الشهادات وملفات التعريف (Certificates & Provisioning)](#ب-تجهيز-الشهادات-وملفات-التعريف-certificates--provisioning)
   - [ج. بناء حزمة IPA الموقعة](#ج-بناء-حزمة-ipa-الموقعة)
   - [د. الرفع عبر Transporter أو Xcode](#د-الرفع-عبر-transporter-أو-xcode)
   - [هـ. إعدادات App Store Connect واجتياز المراجعة](#هـ-إعدادات-app-store-connect-واجتياز-المراجعة)
4. [الأسئلة الشائعة وتفادي أسباب الرفض الشائعة](#4-الأسئلة-الشائعة-وتفادي-أسباب-الرفض-الشائعة)

---

## 1. المتطلبات الأساسية والحسابات

| المتطلب | التفاصيل | التكلفة |
|---|---|---|
| **حساب Google Play Console** | حساب مطور معتمد على Google Play Console | 25 دولار لمرة واحدة مدى الحياة |
| **حساب Apple Developer** | حساب Apple Developer Program باسم فرد أو شركة | 99 دولار سنوياً |
| **رابط سياسة الخصوصية** | رابط عام (URL) مستضاف لسياسة الخصوصية | مجاناً (باستخدام GitHub Pages لملف `privacy_policy.html`) |

---

## 2. الجزء الأول: النشر على Google Play Store

### أ. إنشاء مفتاح التوقيع الرقمي (Upload Keystore)
افتح موجه الأوامر (Terminal / PowerShell) ونفذ الأمر التالي لإنشاء ملف `upload-keystore.jks`:

```bash
keytool -genkey -v -keystore android/app/upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
- سيطلب منك إدخال كلمة مرور (تذكرها جيداً ولا تنساها).
- سيطلب منك اسمك واسم مؤسستك والبلد (يمكنك كتابتها بحرية).

> [!CAUTION]
> **هام جداً:** احتفظ بنسخة احتياطية من ملف `upload-keystore.jks` وكلمة مروره في مكان آمن (مثل Google Drive أو 1Password). إذا فقدت المفتاح لن تتمكن من تحديث التطبيق لاحقاً.

---

### ب. إعداد ملف التوقيع `android/key.properties`
قم بإنشاء ملف باسم `key.properties` داخل مجلد `android/`:
```properties
storePassword=كلمة_مرور_المخزن_التي_اخترتها
keyPassword=كلمة_مرور_المفتاح_التي_اخترتها
keyAlias=upload
storeFile=upload-keystore.jks
```

> [!NOTE]
> ملف `android/app/build.gradle.kts` مهيأ ومبرمج بالفعل لقراءة هذا الملف تلقائياً، وتفعيل التوقيع والتصغير التلقائي (R8/ProGuard) وحماية 16KB ELF Alignment لـ Android 15.

---

### ج. بناء حزمة التطبيق الرسمية (AAB)
نفذ أمر بناء حزمة أندرويد الرسمية بصيغة App Bundle:

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

بعد انتهاء الأمر بنجاح، ستجد الملف الجاهز للرفع في المسار التالي:
`build/app/outputs/bundle/release/app-release.aab`

---

### د. خطوات Google Play Console واستبيان أمان البيانات (Data Safety)

1. **إنشاء التطبيق:**
   - توجه إلى [Google Play Console](https://play.google.com/console).
   - انقر على **"Create App" (إنشاء تطبيق)**.
   - اسم التطبيق: `لقطة - الماسح الضوئي الذكي (Laqta Scanner)`.
   - اللغة الافتراضية: `العربية (ar)`.
   - نوع التطبيق: `App`، والمجانية: `Free`.

2. **بيانات المتجر (Store Listing):**
   - **الوصف القصير (80 حرف):** ماسح ضوئي ذكي للمستندات والبطاقات الشخصية وعقود العمل يعمل بدون إنترنت 100%.
   - **الوصف الكامل:** تطبيق لقطة (Laqta Scanner) هو أداتك الاحترافية المتكاملة لمسح وتعديل المستندات الورقية، واستخراج النصوص بالذكاء الاصطناعي، ودمج بطاقات الرقم القومي A4 بمقياس 1:1، وتوقيع العقود، وحفظ الملفات في خزنة مشفرة عسكرياً (AES-256-GCM) مع إمكانية النسخ الاحتياطي السحابي المشفر بالكامل.
   - **أيقونة التطبيق:** أبعاد 512x512 بكسل (PNG 32-bit).
   - **الرسم المميز (Feature Graphic):** أبعاد 1024x500 بكسل (JPG/PNG).
   - **لقطات الشاشة:** رفع 4 لقطات على الأقل للهاتف ولقطات للأجهزة اللوحية.

3. **رابط سياسة الخصوصية:**
   - انسخ رابط ملف `privacy_policy.html` بعد رفعه على GitHub Pages (مثال: `https://username.github.io/cam_scanner/privacy_policy.html`).

4. **إجابات استبيان أمان البيانات (Data Safety Questionnaire):**
   - هل يجمع التطبيق أي بيانات؟ اختر **No (كلا، التطبيق لا يجمع أي بيانات من المستخدمين)**.
   - هل تتم مشاركة بيانات مع أطراف ثالثة؟ اختر **No**.
   - هل يتم تشفير البيانات أثناء النقل؟ اختر **Yes** (نظراً لدعم التشفير العسكري).

5. **رفع حزمة AAB:**
   - من القائمة الجانبية: **Release > Production** (أو **Internal testing** للاختبار الداخلي أولاً).
   - اسحب ملف `app-release.aab`.
   - اكتب ملاحظات الإصدار (Release Notes): "الإطلاق الرسمي الأول لتطبيق لقطة - مسح ذكي للمستندات وخزنة مشفرة 100% بدون إنترنت."
   - انقر **Save** ثم **Review release** ثم **Start rollout to Production**.

---

## 3. الجزء الثاني: النشر على Apple App Store

### أ. إعداد حساب المطور وتحديد المعرف (Bundle Identifier)
1. افتح موقع [Apple Developer Portal](https://developer.apple.com/account).
2. انتقل إلى **Certificates, Identifiers & Profiles > Identifiers**.
3. أضف معرف جديد لنوع App IDs:
   - الوصف: `Laqta Scanner`
   - المعرف (Bundle ID): `com.yourname.docscanner` (المطابق للمعرف في مشروع Flutter).
   - Capabilities المطلوبة: تأكد من تفعيل **Sign In with Apple** (إن رغبت) أو ترك الإعدادات الافتراضية.

---

### ب. تجهيز الشهادات وملفات التعريف (Certificates & Provisioning)
1. في قسم **Certificates**، أنشئ شهادة **Apple Distribution**.
2. في قسم **Profiles**، أنشئ ملف **App Store Distribution Profile** مرتبط بمعرف التطبيق والشهادة.

---

### ج. بناء حزمة IPA الموقعة
على جهاز ماك (macOS)، افتح سطر الأوامر داخل مجلد المشروع:

```bash
flutter clean
flutter pub get
flutter build ipa --release
```

سيتولى Flutter بناء الحزمة وأرشفتها في المسار:
`build/ios/archive/Runner.xcarchive`

---

### د. الرفع عبر Transporter أو Xcode

**الطريقة الأولى: عبر تطبيق Apple Transporter (الأسهل والأسرع):**
1. حمّل تطبيق **Transporter** مجاناً من متجر برامج الماك (Mac App Store).
2. سجل دخولك بحساب Apple Developer الخاص بك.
3. افتح ملف `build/ios/ipa/cam_scanner.ipa` داخل Transporter.
4. انقر على **Deliver (تسليم)**. سيتم رفع الحزمة والتحقق من صحتها في غضون دقائق.

**الطريقة الثانية: عبر Xcode:**
1. افتح مجلد `ios/Runner.xcworkspace` في Xcode.
2. اختر **Product > Archive**.
3. بعد اكتمال الأرشفة في نافذة Organizer، اختر **Distribute App > App Store Connect > Upload**.

---

### هـ. إعدادات App Store Connect واجتياز المراجعة

1. **إنشاء التطبيق في [App Store Connect](https://appstoreconnect.apple.com):**
   - اختر **My Apps > (+)** > **New App**.
   - المنصة: `iOS`.
   - الاسم: `لقطة: ماسح ضوئي ومستندات` (Laqta Scanner).
   - اللغة: `Arabic`.
   - الـ Bundle ID: اختر `com.yourname.docscanner`.
   - الـ SKU: أي رمز فريد مثل `LAQTA-SCAN-01`.

2. **خصوصية التطبيق (App Privacy):**
   - في صفحة **App Privacy**، انقر **Get Started**.
   - اختر: **"No, we do not collect data from this app" (لا، نحن لا نجمع أي بيانات من هذا التطبيق)**.
   - هذا يمنح التطبيق شارة الخصوصية الذهبية على المتجر ("Data Not Collected").

3. **لقطات الشاشة المطلوبة:**
   - لقطات شاشة مقاس 6.7 بوصة (iPhone 16 Pro Max / 15 Pro Max).
   - لقطات شاشة مقاس 6.5 بوصة أو 5.5 بوصة للأجهزة الأقدم.
   - لقطات شاشة مقاس 12.9 بوصة (iPad Pro) إن تم تمكين دعم الآيباد.

4. **ملاحظات المراجعة لفريق آبل (Review Notes):**
   - اكتب باللغة الإنجليزية في حقل Review Notes:
   > *"This app operates 100% offline. All document scanning, OCR, PDF generation, and encryption are processed locally on the user's device with zero cloud tracking. The app includes a local Secret Vault protected by local Face ID / PIN, and an optional encrypted zero-knowledge backup that users can export to their personal iCloud Drive or Google Drive."*

5. **إرسال للمراجعة:**
   - اختر الحزمة (Build) المرفوعة عبر Transporter.
   - انقر **Save** ثم **Submit for Review**.
   - تستغرق مراجعة آبل عادة من 12 إلى 24 ساعة.

---

## 4. الأسئلة الشائعة وتفادي أسباب الرفض الشائعة

### 1. كيف أتفادى رفض آبل لطلب صلاحيات الكاميرا أو الصور؟
- **الحل:** قمنا بصياغة نصوص وصف واضحة ومقنعة ثنائية اللغة في `ios/Runner/Info.plist` تشرح بدقة سبب الحاجة للكاميرا لمسح المستندات واستيراد الصور واستخدام Face ID لحماية الخزنة، وهو ما يطابق معايير Apple HIG 100%.

### 2. كيف أتفادى متطلب Google Play لـ 16KB Page Alignment؟
- **الحل:** ملف `android/app/build.gradle.kts` يستخدم بالفعل أحدث مكتبات OpenCV 4.11 و CameraX 1.4.2 و Tesseract 5.5 المصممة والمتوافقة كلياً مع معايير الـ 16KB ELF Alignment المفروضة في أندرويد 15.

### 3. أين يمكنني استضافة رابط سياسة الخصوصية مجاناً؟
- يمكنك رفع ملف `privacy_policy.html` الموجود بالمشروع إلى خدمة **GitHub Pages** مجاناً في دقيقة واحدة:
  1. ادخل على مستودعك على GitHub.
  2. انتقل إلى **Settings > Pages**.
  3. اختر Branch: `master` والمسار: `/ (root)`.
  4. انقر **Save** وستحصل على رابط عام دائم يبدأ بـ `https://yousefmoh2399.github.io/cam_scanner/privacy_policy.html`.
