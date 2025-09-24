plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.class_rep"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("release") {
            val propertiesFile = project.file("../key.properties")
            if (propertiesFile.exists()) {
                val properties = java.util.Properties()
                properties.load(java.io.FileInputStream(propertiesFile))
                keyAlias = properties.getProperty("keyAlias")
                keyPassword = properties.getProperty("keyPassword")
                storeFile = file(properties.getProperty("storeFile"))
                storePassword = properties.getProperty("storePassword")
            }
        }
    }

    defaultConfig {
        // TODO: IMPORTANT! Change this to your own unique Application ID before publishing.
        // It cannot be changed after you release the app.
        applicationId = "com.yourcompany.classrep"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            // This now correctly uses your release key.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}