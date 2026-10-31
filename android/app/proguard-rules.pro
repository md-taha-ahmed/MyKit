# Manga extensions are loaded at runtime and link against host classes by name,
# so nothing may be renamed (mirrors Mihon's proguard-rules.pro).
-dontobfuscate

# Injekt reads the injected type from the generic superclass of its type tokens
# (`object : FullTypeReference<T>() {}`); without Signature the release build fails
# with "TypeReference constructed without actual type information".
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod
-keep,allowshrinking class * extends uy.kohesive.injekt.api.FullTypeReference

# Extension API ported from Mihon + MyKit's host.
-keep class eu.kanade.tachiyomi.** { *; }
-keep class tachiyomi.** { *; }
-keep class mihon.** { *; }
-keep class logcat.** { *; }

# Libraries extensions use directly.
-keep,allowoptimization class androidx.preference.** { public protected *; }
-keep,allowoptimization class kotlin.** { public protected *; }
-keep,allowoptimization class kotlinx.coroutines.** { public protected *; }
-keep,allowoptimization class kotlinx.serialization.** { public protected *; }
-keep,allowoptimization class okhttp3.** { public protected *; }
-keep,allowoptimization class okio.** { public protected *; }
-keep,allowoptimization class org.jsoup.** { public protected *; }
-keep,allowoptimization class rx.** { public protected *; }
-keep,allowoptimization class app.cash.quickjs.** { public protected *; }
-keep,allowoptimization class uy.kohesive.injekt.** { public protected *; }
-keep,allowoptimization class com.squareup.zstd.** { public protected *; }

-keepclassmembers class * implements java.io.Serializable {
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# RxJava 1.x
-dontwarn sun.misc.**
-keepclassmembers class rx.internal.util.unsafe.*ArrayQueue*Field* {
    long producerIndex;
    long consumerIndex;
}
-keepclassmembers class rx.internal.util.unsafe.BaseLinkedQueueProducerNodeRef {
    rx.internal.util.atomic.LinkedQueueNode producerNode;
}
-keepclassmembers class rx.internal.util.unsafe.BaseLinkedQueueConsumerNodeRef {
    rx.internal.util.atomic.LinkedQueueNode consumerNode;
}

# OkHttp
-keepclasseswithmembers class okhttp3.MultipartBody$Builder { *; }

# kotlinx.serialization
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep class kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.** { <methods>; }

-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn com.google.re2j.**
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**

# libtorrent4j: SWIG/JNI bindings are looked up by name from native code.
-keep class org.libtorrent4j.** { *; }

# Aniyomi anime extensions link against these by name too.
-keep class fi.iki.elonen.** { *; }

# --- YouTube Shorts: NewPipeExtractor + Rhino (YouTube's player JS) --------
# Rhino references desktop-only Java classes it never uses on Android.
-dontwarn java.beans.**
-dontwarn javax.script.**
-dontwarn jdk.dynalink.**
# Rhino and the extractor load classes by reflection (same rules as NewPipe).
-keep class org.mozilla.javascript.** { *; }
-keep class org.mozilla.classfile.ClassFileWriter
-keep class org.schabi.newpipe.extractor.timeago.patterns.** { *; }
-keep class org.schabi.newpipe.extractor.services.youtube.** { *; }
