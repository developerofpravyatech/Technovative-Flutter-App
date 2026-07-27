allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    afterEvaluate {
        val androidExtension = project.extensions.findByName("android")
        if (androidExtension != null) {
            try {
                val getNamespace = androidExtension.javaClass.getMethod("getNamespace")
                val setNamespace = androidExtension.javaClass.getMethod("setNamespace", String::class.java)
                if (getNamespace.invoke(androidExtension) == null || getNamespace.invoke(androidExtension) == "") {
                    var ns = project.group.toString()
                    if (ns.isEmpty() || ns == "unspecified") {
                        ns = "com.example.${project.name.replace("-", "_").replace(" ", "_")}"
                    }
                    setNamespace.invoke(androidExtension, ns)
                }
            } catch (e: Exception) {
                // Ignore if methods are not accessible
            }

            try {
                for (method in androidExtension.javaClass.methods) {
                    if ((method.name == "setCompileSdk" || method.name == "compileSdkVersion" || method.name == "setCompileSdkVersion") && method.parameterCount == 1) {
                        if (method.parameterTypes[0] == Int::class.java || method.parameterTypes[0] == Int::class.javaObjectType || method.parameterTypes[0] == Number::class.java) {
                            method.invoke(androidExtension, 34)
                        }
                    }
                }
            } catch (e: Exception) {
                // Ignore
            }

            try {
                val getCompileOptions = androidExtension.javaClass.getMethod("getCompileOptions")
                val compileOptions = getCompileOptions.invoke(androidExtension)
                for (method in compileOptions.javaClass.methods) {
                    if ((method.name == "setSourceCompatibility" || method.name == "setTargetCompatibility") && method.parameterCount == 1) {
                        method.invoke(compileOptions, JavaVersion.VERSION_11)
                    }
                }
            } catch (e: Exception) {
                // Ignore
            }
        }

        project.tasks.configureEach {
            if (this.javaClass.name.contains("KotlinCompile")) {
                try {
                    val getKotlinOptions = this.javaClass.getMethod("getKotlinOptions")
                    val kotlinOptions = getKotlinOptions.invoke(this)
                    val setJvmTarget = kotlinOptions.javaClass.getMethod("setJvmTarget", String::class.java)
                    setJvmTarget.invoke(kotlinOptions, "11")
                } catch (e: Exception) {
                    // Ignore
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
