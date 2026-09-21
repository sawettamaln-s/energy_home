plugins {
    id("com.google.gms.google-services") version "4.3.15" apply false
}

// ย้ายโฟลเดอร์ build ของ Android ไปไว้ที่ <project>/build ตามที่ Flutter tool
// คาดหวัง (build/app/outputs/flutter-apk/) ไม่งั้น `flutter build apk` จะ build
// ผ่านแต่หาไฟล์ .apk ไม่เจอ (ไฟล์ไปอยู่ที่ android/app/build/ แทน)
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}