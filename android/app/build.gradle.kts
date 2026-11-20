import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma definitiva: la clave vive fuera del proyecto y su contraseña en
// android/key.properties, que git ignora. Sin ese archivo no se puede
// compilar una versión de uso (así nunca sale un APK con otra firma).
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "es.horasyvacaciones.horas_y_vacaciones"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "es.horasyvacaciones.horas_y_vacaciones"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Copia aparte para comparar (rama estetica-unslop): solo si se
        // compila con `flutter build apk --android-project-arg=copia=estetica`. Así se
        // instala junto a la app de siempre, con otro nombre y sus propios
        // datos. Sin la variable, todo queda igual que siempre.
        val copia = (project.findProperty("copia") as String?)?.trim()
        if (!copia.isNullOrEmpty()) {
            applicationIdSuffix = ".$copia"
            manifestPlaceholders["appLabel"] = "Horas ($copia)"
        } else {
            manifestPlaceholders["appLabel"] = "Extras"
        }
    }

    signingConfigs {
        create("release") {
            if (keyProperties.isEmpty) {
                throw GradleException(
                    "Falta android/key.properties: es la contraseña de la firma. " +
                        "Cópialo desde tu copia de seguridad de la clave."
                )
            }
            storeFile = file(keyProperties.getProperty("storeFile"))
            storePassword = keyProperties.getProperty("storePassword")
            keyAlias = keyProperties.getProperty("keyAlias")
            keyPassword = keyProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
