# الدليل الشامل لرفع ونشر تطبيق "لقطة" (Laqta Scanner) على متجري Google Play و Apple App Store للمبتدئين

> **مرحباً بك!** هذا الدليل كُتب خصيصاً ليأخذك خطوة بخطوة من الصفر، وبأبسط أسلوب ممكن، لرفع وتوقيع ونشر تطبيق **"لقطة" (Laqta Scanner)** على متجري **جوجل بلاي (Google Play)** و **آبل ستور (Apple App Store)**، واجتياز مرحلة المراجعة (App Review) بنجاح من المرة الأولى.

---

## 📌 الفهرس العام
1. [نظرة عامة وخريطة الطريق للمبتدئين](#1-نظرة-عامة-وخريطة-الطريق-للمبتدئين)
2. [الخطوة التحضيرية: تفعيل رابط سياسة الخصوصية مجاناً في دقيقتين](#2-الخطوة-التحضيرية-تفعيل-رابط-سياسة-الخصوصية-مجاناً)
3. [القسم الأول: رفع التطبيق على Google Play Store (أندرويد)](#3-القسم-الأول-رفع-التطبيق-على-google-play-store)
   - [أ. إنشاء مفتاح التوقيع الرقمي (Keystore) على ويندوز](#أ-إنشاء-مفتاح-التوقيع-الرقمي-keystore-على-ويندوز)
   - [ب. تجهيز ملف التوقيع key.properties](#ب-تجهيز-ملف-التوقيع-keyproperties)
   - [ج. بناء حزمة التطبيق الرسمية (AAB) المعتمدة](#ج-بناء-حزمة-التطبيق-الرسمية-aab-المعتمدة)
   - [د. إنشاء الحساب والتطبيق في Google Play Console](#د-إنشاء-الحساب-والتطبيق-في-google-play-console)
   - [هـ. تعبئة استبيانات لوحة التحكم (App Content) إجابات نموذجية](#هـ-تعبئة-استبيانات-لوحة-التحكم-app-content)
   - [و. بيانات المتجر الرسمية (Store Listing)](#و-بيانات-المتجر-الرسمية-store-listing)
   - [ز. رفع الـ AAB والإرسال للمراجعة والتنبيه الخاص بالحسابات الجديدة](#ز-رفع-الـ-aab-والإرسال-للمراجعة)
4. [القسم الثاني: رفع التطبيق على Apple App Store (آيفون/آيباد)](#4-القسم-الثاني-رفع-التطبيق-على-apple-app-store)
   - [أ. كيف ترفع تطبيق iOS وأنت تعمل على نظام Windows؟](#أ-كيف-ترفع-تطبيق-ios-وأنت-تعمل-على-نظام-windows)
   - [ب. تجهيز حساب Apple Developer و Bundle Identifier](#ب-تجهيز-حساب-apple-developer-و-bundle-identifier)
   - [ج. بناء حزمة IPA والرفع لـ App Store Connect](#ج-بناء-حزمة-ipa-والرفع-لـ-app-store-connect)
   - [د. إعدادات صفحة التطبيق في App Store Connect](#د-إعدادات-صفحة-التطبيق-في-app-store-connect)
   - [هـ. استبيان خصوصية آبل (App Privacy) وملاحظات المراجع](#هـ-استبيان-خصوصية-آبل-app-privacy-وملاحظات-المراجع)
5. [جدول أبعاد وتصميمات الصور والأيقونات المطلوبة](#5-جدول-أبعاد-وتصميمات-الصور-والأيقونات-المطلوبة)
6. [أسباب الرفض الشائعة وكيفية تفاديها](#6-أسباب-الرفض-الشائعة-وكيفية-تفاديها)

---

## 1. نظرة عامة وخريطة الطريق للمبتدئين

لكي يظهر تطبيقك في المتاجر ويقوم المستخدمون بتحميله، هناك مسار محدد وواضح:

```
[ جهاز الكمبيوتر الخاص بك ]
       │
       ├── 1. تجهيز رابط سياسة الخصوصية (Privacy Policy URL)
       ├── 2. توليد مفتاح التوقيع الرقمي (Release Keystore)
       ├── 3. بناء الحزمة النهائية:
       │      ├── أندرويد: ملف .aab (Android App Bundle)
       │      └── آبل: ملف .ipa (iOS App Store Package)
       │
       ▼
[ منصات المتاجر الرسمية ]
       │
       ├── Google Play Console ──► إدخال الوصف + الصور + أمان البيانات ──► إرسال للمراجعة ──► متاح على متجر أندرويد
       └── App Store Connect   ──► إدخال الوصف + الصور + خصوصية التطبيق ──► إرسال للمراجعة ──► متاح على متجر آبل
```

### ⚠️ تنبيه فائق الأهمية قبل البدء: معرف التطبيق (Package ID / Bundle Identifier)
- معرّف التطبيق هو بصمة التطبيق الفريدة في العالم (مثل رقم الهوية).
- في الأندرويد هو: `applicationId` (الموجود في `android/app/build.gradle.kts`).
- في الآيفون هو: `PRODUCT_BUNDLE_IDENTIFIER` (الموجود في إعدادات Xcode).
- تم ضبط المعرف الرسمي للمشروع ليطابق متجر جوجل بلاي وآبل: `com.laqta.scanner` في أندرويد و iOS.
- **تنبيه:** تم تجهيز وربط حزمة التطبيق بهذا المعرف `com.laqta.scanner` بالكامل وجاهزة للرفع. بمجرد رفع أول نسخة إلى Google Play أو Apple Store، **لا يمكن تغيير هذا المعرف نهائياً**.

---

## 2. الخطوة التحضيرية: تفعيل رابط سياسة الخصوصية مجاناً

تشترط كل من Google و Apple وجود رابط إنترنت علني ومباشر لسياسة الخصوصية قبل الموافقة على التطبيق.
لقد قمنا بتجهيز ملف `privacy_policy.html` بالكامل داخل مجلد المشروع، ويمكنك رفعه والحصول على رابط مباشر مجاناً عبر **GitHub Pages**:

### خطوات تفعيل الرابط في دقيقة واحدة:
1. ارفع مشروعك على مستودع (Repository) في حسابك على [GitHub](https://github.com).
2. من صفحة المستودع على GitHub، اضغط على **Settings** (الإعدادات).
3. من القائمة الجانبية اليسرى، اضغط على **Pages**.
4. تحت عنوان **Branch**: اختر الفرع `master` أو `main`، واجعل المجلد `/(root)`، ثم اضغط **Save**.
5. بعد دقيقة واحدة، سيظهر لك الرابط العلني لسياسة الخصوصية، وسيكون بالشكل التالي:
   ```
   https://<your-username>.github.io/<repository-name>/privacy_policy.html
   ```
> احتفظ بهذا الرابط؛ سنضعه في حقلي سياسة الخصوصية في Google Play و App Store Connect.

---

## 3. القسم الأول: رفع التطبيق على Google Play Store

### المتطلبات الأساسية لحساب جوجل بلاي:
1. التوجه إلى [Google Play Console](https://play.google.com/console).
2. تسجيل الدخول بحساب Google.
3. دفع رسوم التسجيل: **25 دولار تدفع لمرة واحدة مدى الحياة**.
4. استكمال التحقق من الهوية الشخصية (رفع صورة بطاقة الهوية أو جواز السفر وعنوان السكن).

---

### أ. إنشاء مفتاح التوقيع الرقمي (Keystore) على ويندوز
لكي يقبل متجر Google Play حزمة التطبيق، يجب توقيعها بمفتاح أمان خاص بك (Upload Keystore).

1. افتح موجه الأوامر **PowerShell** داخل مجلد المشروع `f:\cam_scanner`.
2. انسخ ونفذ الأمر التالي لإنشاء المفتاح:

```powershell
keytool -genkey -v -keystore android/app/upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

3. ستظهر لك أسئلة متتالية في الشاشة:
   - **Enter keystore password:** اكتب كلمة مرور قوية (مثال: `Pass2026@Scanner`) - *ملاحظة: الأحرف لن تظهر أثناء الكتابة لأسباب أمنية، فقط اكتب واضغط Enter*.
   - **Re-enter new password:** أعد كتابة كلمة المرور واضغط Enter.
   - **What is your first and last name?** اكتب اسمك (مثال: `Yousef Mohamed`).
   - **What is the name of your organizational unit?** اكتب: `Mobile Dev`.
   - **What is the name of your organization?** اكتب: `Laqta Apps`.
   - **What is the name of your City or Locality?** اكتب مدينتك (مثال: `Cairo`).
   - **What is the name of your State or Province?** اكتب محافظتك (مثال: `Cairo`).
   - **What is the two-letter country code?** اكتب رمز دولتك بحرفين (مثال: `EG` أو `SA`).
   - **Is CN=... correct?** اكتب `yes` واضغط Enter.

> 🔴 **تحذير شديد الأهمية:** خذ نسخة من ملف `android/app/upload-keystore.jks` وكلمة المرور واحفظها في فلاشة أو Google Drive خاص بك. إذا حذفت هذا الملف مستقبلاً لن تتمكن من تحديث التطبيق على جوجل بلاي أبداً.

---

### ب. تجهيز ملف التوقيع `key.properties`
الآن نريد إخبار نظام البناء في المشروع بكلمة المرور واسم المفتاح تلقائياً:

1. أنشئ ملفاً جديداً باسم `key.properties` وضعه داخل مجلد `android/` مباشرة:
   - المسار الكامل: `android/key.properties`
2. ضع داخل الملف المحتوى التالي (مع استبدال كلمة المرور بما كتبته):

```properties
storePassword=Pass2026@Scanner
keyPassword=Pass2026@Scanner
keyAlias=upload
storeFile=upload-keystore.jks
```

> ملف `android/app/build.gradle.kts` مهيأ ومبرمج بالفعل لقراءة هذا الملف تلقائياً فور وجوده وتطبيق التوقيع والتصغير R8 وحماية الـ 16KB Alignment للأندرويد 15.

---

### ج. بناء حزمة التطبيق الرسمية (AAB) المعتمدة
متجر Google Play لا يقبل ملفات APK العادية للنشر الأول، بل يشترط حزمة **Android App Bundle (.aab)** لأنها تُقلل حجم التطبيق للمستخدم بنسبة 60%.

نفذ الأمر التالي في PowerShell:

```powershell
flutter clean
flutter pub get
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

فور انتهاء البناء بنجاح، ستجد الملف الجاهز للرفع في المسار التالي:
📁 `build\app\outputs\bundle\release\app-release.aab`

---

### د. إنشاء الحساب والتطبيق في Google Play Console
1. ادخل على [Google Play Console](https://play.google.com/console).
2. في الزاوية العلوية، انقر على زر **Create app (إنشاء تطبيق)**.
3. املأ الخانات الأولية:
   - **App name:** `لقطة - ماسح ضوئي ذكي وPDF`
   - **Default language:** `العربية - ar`
   - **App or game:** اختر `App`
   - **Free or paid:** اختر `Free` (مجاني)
   - وافق على الشروط والسياسات ثم اضغط **Create app**.

---

### هـ. تعبئة استبيانات لوحة التحكم (App Content)
ستظهر لك في الصفحة الرئيسية قائمة مهام إجبارية تحت قسم **Set up your app**. قم بإكمالها بالترتيب التالي:

1. **Privacy policy (سياسة الخصوصية):**
   - ضع رابط صفحة سياسة الخصوصية الذي أنشأته على GitHub Pages.
2. **App access (وصول التطبيق):**
   - اختر: **All functionality is available without special access** (كافة الوظائف متاحة بدون تسجيل دخول أو قيود خاصة).
3. **Ads (الإعلانات):**
   - اختر: **No, my app does not contain ads** (تطبيق لقطة خالٍ تماماً من الإعلانات).
4. **Content rating (تقييم المحتوى - IARC):**
   - أدخل بريدك الإلكتروني.
   - اختر الفئة: **Utility, Productivity, Communication, or Other**.
   - أجب بـ **No** على كافة أسئلة العنف، المخدرات، الألفاظ البذيئة، ومشاركة الموقع الجغرافي.
   - اضغط Save ثم Summary ثم Submit (ستحصل على تقييم مناسب لجميع الأعمار PEGI 3 / Everyone).
5. **Target audience (الفئة المستهدفة):**
   - اختر الفئات العمرية من **18 and over** (أو 13 وما فوق).
   - هل التطبيق موجه للأطفال؟ اختر **No**.
6. **News apps (تطبيقات الأخبار):** اختر **No**.
7. **COVID-19 contact tracing:** اختر **My app is not publicly available COVID-19 app**.
8. **Data safety (أمان البيانات - أهم قسم):**
   - هل يجمع التطبيق أو يشارك بيانات المستخدم؟ اختر **No (كلا)**.
   - *تطبيق لقطة يعمل 100% بدون إنترنت ولا توجد أي خوادم خارجية.*
   - اضغط Save ثم Submit.
9. **Financial features / Government apps:** اختر **My app does not provide any financial or government features**.

---

### و. بيانات المتجر الرسمية (Store Listing)
انتقل من القائمة الجانبية إلى **Grow > Store presence > Main store listing**:

- **App name (اسم التطبيق):** `لقطة - ماسح ضوئي ذكي وPDF`
- **Short description (الوصف القصير):** `ماسح مستندات ذكي يعمل 100% بدون إنترنت مع مسح الهوية والـ OCR وخزنة مشفرة`
- **Full description (الوصف الكامل):** انسخ النص الكامل الجاهز من ملف `STORE_LISTING_METADATA.md` والصقه هنا مباشرة.
- **App icon (أيقونة التطبيق):** صورة بدقة `512x512` بصيغة PNG (خلفية ملونة بدون شفافية).
- **Feature graphic (الرسم المميز):** صورة بدقة `1024x500` بصيغة JPG أو PNG.
- **Phone screenshots (لقطات الشاشة):** ارفع من 4 إلى 8 لقطات شاشة واضحة للتطبيق.
- اضغط **Save**.

---

### ز. رفع الـ AAB والإرسال للمراجعة
1. من القائمة الجانبية، اذهب إلى: **Release > Production**.
2. اضغط على **Create new release (إنشاء إصدار جديد)**.
3. في مربع **App bundles**: اسحب وأفلت ملف `app-release.aab` الموجود في `build\app\outputs\bundle\release\`.
4. في خانة **Release notes (ملاحظات الإصدار)** اكتب:
   ```text
   الإطلاق الرسمي الأول لتطبيق لقطة:
   - مسح ذكي للمستندات والبطاقات الشخصية A4 بمقياس 1:1.
   - استخراج النصوص بالذكاء الاصطناعي (OCR) بدون إنترنت.
   - خزنة سرية مشفرة بتقنية AES-256-GCM.
   - استوديو تحويل ومسح المجسمات 3D ومشاركتها عبر WebDrop.
   ```
5. اضغط **Next** ثم راجع التقرير واضغط **Save** ثم **Send for review (إرسال للمراجعة)**.

> 💡 **ملاحظة خاصة بحسابات جوجل بلاي الشخصية الجديدة (2024-2026):**
> إذا كان حسابك جديداً ومسجلاً كفرد (Personal Account)، تشترط جوجل تجربة مغلقة (Closed Testing) تشارك فيها التطبيق مع 20 مختبراً يفتحونه لمدة 14 يوماً قبل فتح خيار الـ Production. يمكنك دعوة 20 صديقاً عبر إضافة إيميلاتهم في قسم Closed Testing وتثبيت التطبيق على هواتفهم، وبعد 14 يوماً تضغط زر "Apply for Production" وتوافق جوجل فوراً. أما إذا كان حسابك تجارياً (Organization)، فستنشر مباشرة للـ Production بدون هذا الشرط.

---

## 4. القسم الثاني: رفع التطبيق على Apple App Store

### المتطلبات الأساسية لحساب آبل:
1. حساب [Apple Developer Program](https://developer.apple.com/programs/).
2. التكلفة: **99 دولار سنوياً**.
3. التسجيل يتم بسهولة عبر تحميل تطبيق **Apple Developer** على أي جهاز آيفون أو آيباد واستكمال الدفع عبر Apple Pay / البطاقة.

---

### أ. كيف ترفع تطبيق iOS وأنت تعمل على نظام Windows؟
بما أنك تستخدم كمبيوتر ويندوز، فنظام macOS وبرنامج Xcode ضروريان لبناء حزمة iOS. أمامك 3 خيارات سهلة:

1. **الخيار الأول (الأسهل والأضمن):** استخدام جهاز ماك لصديق أو في العمل لمدة نصف ساعة فقط:
   - تنسخ مجلد المشروع إلى الماك، وتفتح Terminal وتنفذ `flutter build ipa --release`، ثم ترفع الملف ببرنامج Transporter بنقرة واحدة.
2. **الخيار الثاني (مجاني بالكامل وبدون ماك):** استخدام **GitHub Actions**:
   - توفر GitHub خوادم Mac مجانية (macOS Runners) تقوم بتجميع كود Flutter وتوليد ملف الـ IPA ورفعه لـ App Store Connect تلقائياً عند عمل Git Push.
3. **الخيار الثالث:** استخدام خدمات سحابية مثل [Codemagic](https://codemagic.io) أو MacInCloud؛ حيث ترتبط بمشروعك وتقوم بعملية البناء السحابي والرفع مباشرة.

---

### ب. تجهيز حساب Apple Developer و Bundle Identifier
1. ادخل على [developer.apple.com](https://developer.apple.com) وسجل الدخول بحسابك.
2. انتقل إلى **Certificates, Identifiers & Profiles > Identifiers**.
3. اضغط على علامة `(+)` لإضافة App ID جديد:
   - **Type:** `App IDs` ثم اختر `App`.
   - **Description:** `Laqta Scanner`
   - **Bundle ID:** اختر `Explicit` واكتب المعرف (مثال: `com.laqta.scanner`).
   - اضغط **Continue** ثم **Register**.

---

### ج. بناء حزمة IPA والرفع لـ App Store Connect
على جهاز الماك، افتح Terminal في مجلد المشروع ونفذ:

```bash
flutter clean
flutter pub get
flutter build ipa --release
```

سيتولى Flutter بناء الحزمة الموقعة وتوليد ملفين:
- `build/ios/archive/Runner.xcarchive`
- `build/ios/ipa/cam_scanner.ipa`

#### كيفية الرفع بضغطة زر عبر تطبيق Transporter:
1. افتح تطبيق **Transporter** (متاح مجاناً على Mac App Store).
2. سجل دخولك بنفس حساب Apple Developer.
3. اسحب ملف `cam_scanner.ipa` وأفلته داخل النافذة.
4. اضغط زر **Deliver (تسليم)**. سيكتمل الرفع والتحقق خلال دقائق معدودة.

---

### د. إعدادات صفحة التطبيق في App Store Connect
1. ادخل على [App Store Connect](https://appstoreconnect.apple.com).
2. اذهب إلى **My Apps** واضغط علامة `(+)` ثم **New App**:
   - **Platforms:** `iOS`
   - **Name:** `لقطة: ماسح ضوئي ومستندات`
   - **Primary Language:** `Arabic`
   - **Bundle ID:** اختر المعرف الذي سجلته (`com.laqta.scanner`).
   - **SKU:** اكتب أي رمز إداري فريد (مثال: `LAQTA-SCAN-2026`).
   - **User Access:** `Full Access`.
   - اضغط **Create**.

3. في صفحة التطبيق:
   - **Subtitle (العنوان الفرعي):** `مسح ضوئي بدون إنترنت وخزنة`
   - **Category (الفئة):** `Productivity` (الفئة الثانوية: `Utilities`).
   - **Description (الوصف):** الصق الوصف الكامل من ملف `STORE_LISTING_METADATA.md`.
   - **Keywords (الكلمات الدلالية):** `ماسح,scanner,pdf,ocr,وثائق,بطاقة الهوية,كام سكانر,خزنة,تشفير,camscanner,عقود,مستندات,stl,3d`
   - **Support URL & Marketing URL:** رابط موقعك أو رابط سياسة الخصوصية.

---

### هـ. استبيان خصوصية آبل (App Privacy) وملاحظات المراجع

#### 1. استبيان App Privacy (تغذية الخصوصية):
- من القائمة الجانبية، اضغط **App Privacy**.
- اضغط **Get Started**.
- سيظهر لك سؤال: *"Do you or your third-party partners collect data from this app?"*
- اختر: **No, we do not collect data from this app**.
- هذا الاختيار سيمنح تطبيقك شارة آبل الرسمية المميزة: **"Data Not Collected"** (لا يتم جمع البيانات).

#### 2. خانة ملاحظات المراجع (Review Notes):
في صفحة الإصدار، هناك حقل إلزامي يقرأه مهندس آبل الذي سيراجع تطبيقك. انسخ والصق فيه هذا النص الإنجليزي بالكامل:

```text
Dear Apple App Review Team,

Laqta Scanner is designed strictly under the "Privacy by Design" principle.
Key architectural highlights for review:
1. 100% Offline: The app does not connect to any proprietary backend server. All document scanning, edge detection, OpenCV perspective transforms, OCR, and 3D STL reconstructions are executed strictly on-device.
2. Camera Permission: Used exclusively for scanning physical documents, ID cards, and 3D objects in real-time. No frames or videos are recorded or dispatched externally.
3. Face ID / Biometrics: Used exclusively to authenticate access to the local AES-256-GCM encrypted Secret Vault. To review the vault, simply navigate to the 'الخزنة' tab, set any temporary 4-6 digit passcode, and test the encryption.
4. WebDrop Feature: Hosts a lightweight local HTTP server strictly on the local Wi-Fi subnet to allow local wireless PDF export between the device and desktop browser.
5. Zero Cloud Tracking: No third-party ad networks or analytics SDKs are incorporated.

Thank you for your review.
```

#### 3. إرسال للمراجعة:
- اختر الـ Build الذي تم رفعه بواسطة Transporter.
- اضغط **Save** ثم **Add for Review** ثم **Submit to App Review**.
- تستغرق مراجعة آبل عادة ما بين **8 ساعات إلى 24 ساعة** لتصلك رسالة القبول الرسمية ويصبح التطبيق متاحاً على المتجر فوراً.

---

## 5. جدول أبعاد وتصميمات الصور والأيقونات المطلوبة

| المتجر | العنصر | المقاس الإلزامي (بالبكسل) | الصيغة | ملاحظات هامة |
|---|---|---|---|---|
| **Google Play** | أيقونة التطبيق (App Icon) | 512 × 512 | PNG (32-bit) | خلفية ممتلئة بدون زوايا دائرية وبدون شفافية |
| **Google Play** | الرسم المميز (Feature Graphic) | 1024 × 500 | JPG أو PNG | يظهر كغلاف علوي لصفحة التطبيق |
| **Google Play** | لقطات الشاشة للهاتف | نسبة 16:9 أو 18:9 (مثال: 1080×2400) | JPG أو PNG | على الأقل 4 صور |
| **Google Play** | لقطات شاشة للأجهزة اللوحية (Tablet) | شاشات 7 و 10 بوصة | JPG أو PNG | اختيارية لكن تمنحك شارة التوافق الكامل |
| **App Store** | لقطات آيفون شاشة 6.7" (Max) | 1290 × 2796 أو 1320 × 2868 | PNG أو JPG | أجهزة iPhone 16 Pro Max / 15 Pro Max |
| **App Store** | لقطات آيفون شاشة 6.5" | 1242 × 2688 | PNG أو JPG | أجهزة iPhone 11 Pro Max / XS Max |
| **App Store** | لقطات آيباد 12.9" (إن رغبت) | 2048 × 2732 | PNG أو JPG | للأجهزة اللوحية iPad Pro |

---

## 6. أسباب الرفض الشائعة وكيفية تفاديها

| سبب الرفض الشائع | لماذا يرفض المتجر؟ | كيف تفاديناه في تطبيق لقطة بنسبة 100%؟ |
|---|---|---|
| **صلاحيات التخزين الواسعة (MANAGE_EXTERNAL_STORAGE)** | يرفض جوجل أي تطبيق يطلب هذا الإذن ما لم يكن مدير ملفات. | تطبيقنا لا يطلب هذا الإذن إطلاقاً؛ يعتمد على مساحة التخزين الخاصة والآمنة (Scoped Storage). |
| **نصوص أذونات آبل غير واضحة في Info.plist** | ترفض آبل التطبيق إذا كان سبب طلب الكاميرا أو الصور عاماً أو مقتضباً. | تم وضع نصوص تفصيلية بالعربية والإنجليزية تشرح بدقة سبب كل إذن في `Info.plist`. |
| **توافقية 16KB Page Alignment (أندرويد 15)** | سترفض جوجل أي حزم بها مكتبات C++ قديمة لا تدعم 16KB ELF alignment. | قمنا بتحديث OpenCV 4.11 و CameraX 1.4.2 و Tesseract 5.5 المتوافقة مع معايير أندرويد 15. |
| **عدم عمل الميزات بدون إنترنت** | إذا ذكرت في الوصف "أوفلاين" واكتشف المراجع طلب اتصال بالإنترنت للوظيفة. | كافة وظائف المسح، والـ OCR، والخزنة، ومجسمات 3D تعمل بالكامل بدون إنترنت، وهو ما تم توضيحه للمراجع. |
| **رابط سياسة خصوصية معطل** | يفحص مراجعو المتجر الرابط آلياً؛ إذا أعطى 404 يتم الرفض فوراً. | الرابط مستضاف على GitHub Pages بملف HTML كامل وثابت لا ينقطع. |

---

### 🎉 ملخص ختامي:
كل شيء في كود المشروع الآن من ملفات Manifest و Info.plist والـ ProGuard وإعدادات الخصوصية والنسخة التجريبية Beta مضبوط وفق أعلى المعايير القياسية لعام 2026.
اتبع الخطوات أعلاه بالترتيب، وستكون نسختك الأولى منشورة على أكبر متجرين في العالم بكل سلاسة!
