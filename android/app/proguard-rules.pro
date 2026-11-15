# Flutter and its plugins register entry points reflectively.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# media_kit loads libmpv through JNI; the bindings must survive shrinking.
-keep class com.alexmercerind.** { *; }
-keep class media_kit_video.** { *; }
-dontwarn com.alexmercerind.**

# The media session's callbacks are invoked by the framework.
-keep class androidx.media.** { *; }
-keep class android.support.v4.media.** { *; }

# This app's own platform bridge.
-keep class com.botsailer.depressedzone.** { *; }
