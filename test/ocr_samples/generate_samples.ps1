Add-Type -AssemblyName System.Drawing

$outDir = "g:\cam_scanner\test\ocr_samples"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Save-Sample {
    param(
        [string]$BaseName,
        [string]$GroundTruth,
        [double]$RotateDeg = 0.0,
        [bool]$UnevenLighting = $false,
        [bool]$DrawTable = $false,
        [bool]$IsRtl = $true
    )

    $txtPath = Join-Path $outDir "$BaseName.txt"
    [System.IO.File]::WriteAllText($txtPath, $GroundTruth.Trim(), [System.Text.Encoding]::UTF8)

    $w = 1400
    $h = 1000
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    if ($UnevenLighting) {
        # Simulate camera uneven shadow gradient + paper tone
        $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
        $c1 = [System.Drawing.Color]::FromArgb(245, 244, 240)
        $c2 = [System.Drawing.Color]::FromArgb(145, 142, 136)
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 28.0)
        $g.FillRectangle($grad, $rect)
        $grad.Dispose()
    } else {
        $g.Clear([System.Drawing.Color]::White)
    }

    if ($RotateDeg -ne 0.0) {
        $g.TranslateTransform($w / 2.0, $h / 2.0)
        $g.RotateTransform([float]$RotateDeg)
        $g.TranslateTransform(-$w / 2.0, -$h / 2.0)
    }

    $font = New-Object System.Drawing.Font("Arial", 28, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(22, 22, 22))
    $sf = New-Object System.Drawing.StringFormat
    if ($IsRtl) {
        $sf.FormatFlags = [System.Drawing.StringFormatFlags]::DirectionRightToLeft
        $sf.Alignment = [System.Drawing.StringAlignment]::Near
    } else {
        $sf.Alignment = [System.Drawing.StringAlignment]::Near
    }

    $lines = $GroundTruth.Trim() -split "`r?`n"
    $y = 110
    $linePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, 70, 70), 2)

    if ($DrawTable) {
        $g.DrawRectangle($linePen, 90, 90, $w - 180, ($lines.Count * 76) + 30)
    }

    foreach ($line in $lines) {
        if ($DrawTable) {
            $g.DrawLine($linePen, 90, $y + 58, $w - 90, $y + 58)
        }
        $layoutRect = [System.Drawing.RectangleF]::new([float]110, [float]$y, [float]($w - 220), [float]68)
        $g.DrawString($line, $font, $brush, $layoutRect, $sf)
        $y += 74
    }

    if ($UnevenLighting) {
        # Add deterministic sensor grain noise on skewed noisy sample
        $rng = New-Object System.Random(42)
        for ($i = 0; $i -lt 18000; $i++) {
            $nx = $rng.Next(40, $w - 40)
            $ny = $rng.Next(40, $h - 40)
            $v = $rng.Next(75, 165)
            $bmp.SetPixel($nx, $ny, [System.Drawing.Color]::FromArgb($v, $v, $v))
        }
    }

    $pngPath = Join-Path $outDir "$BaseName.png"
    $bmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)

    $linePen.Dispose()
    $sf.Dispose()
    $brush.Dispose()
    $font.Dispose()
    $g.Dispose()
    $bmp.Dispose()
}

# 1. Sample 1: Arabic Clean
$s1 = @"
بسم الله الرحمن الرحيم
عقد تقديم خدمات تقنية وبرمجيات محلية
الطرف الأول شركة المسح الضوئي الذكي للأنظمة الرقمية
الطرف الثاني مؤسسة الحلول المتكاملة لإدارة الوثائق
يلتزم الطرف الأول بتسليم النظام كاملا دون اتصال بالإنترنت
جميع البيانات تحفظ محليا على جهاز المستخدم بأعلى معايير الأمان
"@
Save-Sample -BaseName "sample1_arabic_clean" -GroundTruth $s1 -RotateDeg 0.0 -UnevenLighting $false -DrawTable $false -IsRtl $true

# 2. Sample 2: Arabic Skewed (-5.5 deg tilt) + Uneven Illumination Shadow + Grain
$s2 = @"
إشعار استلام مستندات رسمية ومالية
تاريخ الاستلام الخامس عشر من شهر سبتمبر عام ألفين وستة وعشرين
تم فحص جميع الصفحات الممسوحة ضوئيا والتأكد من وضوح النصوص العربية
يعتمد هذا المستند محليا داخل الخزنة المشفرة للتطبيق
رقم المرجع الداخلي للمعاملة أربعة آلاف وثمانمائة واثنان وسبعون
"@
Save-Sample -BaseName "sample2_arabic_skewed_noisy" -GroundTruth $s2 -RotateDeg -5.5 -UnevenLighting $true -DrawTable $false -IsRtl $true

# 3. Sample 3: English Clean
$s3 = @"
OFFLINE DOCUMENT SCANNER TECHNICAL SPECIFICATION
All image enhancement and perspective correction run locally on device.
Zero network packets are transmitted during OCR or PDF generation.
Supported document formats include searchable PDF and encrypted vault archives.
Verified compatibility with Android 15 and 16KB memory page alignment.
"@
Save-Sample -BaseName "sample3_english_clean" -GroundTruth $s3 -RotateDeg 0.0 -UnevenLighting $false -DrawTable $false -IsRtl $false

# 4. Sample 4: Mixed Arabic + English + Numbers
$s4 = @"
تقرير الفحص الفني رقم 2026-0984 لنظام DocScanner Pro
إصدار المحرك المحلي OpenCV 4.11.0 مع مكتبة Tesseract 5.5.1
عدد الصفحات المعالجة 145 صفحة بدقة 300 DPI خلال 820 ملي ثانية
نسبة التطابق في الحروف العربية تتجاوز 96 بالمئة على المستندات المطبوعة
"@
Save-Sample -BaseName "sample4_mixed_ara_eng_numbers" -GroundTruth $s4 -RotateDeg 0.0 -UnevenLighting $false -DrawTable $false -IsRtl $true

# 5. Sample 5: Table / Invoice (Arabic + Numbers)
$s5 = @"
فاتورة ضريبية مبسطة رقم 774209 بتاريخ 2026/09/29
البند الأول رخصة تشغيل نظام أرشفة محلي الكمية 2 السعر 1500 ريال
البند الثاني وحدة مسح البطاقات والهويات الكمية 5 السعر 2250 ريال
البند الثالث خزنة تشفير المستندات الحساسة الكمية 1 السعر 950 ريال
الإجمالي النهائي شامل الضريبة المضافة 4700 ريال سعودي فقط
"@
Save-Sample -BaseName "sample5_table_invoice" -GroundTruth $s5 -RotateDeg 0.0 -UnevenLighting $false -DrawTable $true -IsRtl $true

Write-Output "Generated 5 OCR samples + Ground Truth .txt files in $outDir"
