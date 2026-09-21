plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.energy_home"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true  // ← เพิ่มตรงนี้
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.energy_home"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true  // ← เพิ่มตรงนี้
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")

            // เปิด R8 ย่อโค้ด/รีซอร์สตอน release และชี้ไปที่ proguard-rules.pro
            // (กฎของ Gson ที่ flutter_local_notifications ใช้เก็บ scheduled
            // notification) — ถ้าไม่ระบุ proguardFiles ไฟล์กฎของโปรเจกต์จะไม่ถูกใช้
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {  // ← เพิ่มบรรทัดนี้ทั้งหมด
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}