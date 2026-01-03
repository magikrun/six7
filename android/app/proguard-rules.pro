# JNA ProGuard rules - required for UniFFI bindings
-dontwarn java.awt.*
-dontwarn sun.reflect.*
-dontwarn com.sun.jna.platform.win32.*
-dontwarn com.sun.jna.platform.wince.*

# Keep all JNA classes
-keep class com.sun.jna.** { *; }
-keepclassmembers class com.sun.jna.** { *; }

# Keep JNA Pointer class and its fields (critical for UniFFI)
-keepclassmembers class com.sun.jna.Pointer {
    long peer;
}

# Keep all Structure subclasses
-keep class * extends com.sun.jna.Structure { *; }
-keepclassmembers class * extends com.sun.jna.Structure { *; }

# Keep all Callback implementations
-keep class * implements com.sun.jna.Callback { *; }
-keepclassmembers class * implements com.sun.jna.Callback { *; }

# Keep UniFFI generated code
-keep class uniffi.korium.** { *; }
-keepclassmembers class uniffi.korium.** { *; }

# Keep native method names
-keepclasseswithmembernames class * {
    native <methods>;
}
