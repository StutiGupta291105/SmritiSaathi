# Keep rules the release build needs (R8 shrinks and renames code in release).
#
# flutter_local_notifications stores each scheduled reminder with Gson, which reads
# the generic types of its classes at run time. R8 strips that information and
# scheduling then fails in the installed app ("Missing type parameter") while it
# works in debug: reminders silently never ring. These rules keep what Gson needs.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
