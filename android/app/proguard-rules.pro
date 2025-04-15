# Flutter specific rules.
# ...existing code...

# Keep rules for com.google.crypto.tink and related annotations
-keep class com.google.errorprone.annotations.** { *; }
-keep class javax.annotation.** { *; }
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
