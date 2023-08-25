import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    kotlin("jvm") version "1.9.0"
    application
}

group = "org.rebo"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

dependencies {
//    testImplementation(kotlin("test"))
    testImplementation("io.kotest:kotest-property:5.6.2")
    testImplementation("io.kotest:kotest-runner-junit5-jvm:5.6.2")
}

tasks.test {
    useJUnitPlatform()
}

tasks.withType<KotlinCompile> {
    kotlinOptions.jvmTarget = "1.8"
//    kotlinOptions.jvmTarget = "16"
}

application {
    mainClass.set("MainKt")
}