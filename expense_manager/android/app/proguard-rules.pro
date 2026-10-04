# ML Kit text recognition: only the Latin model is bundled; the plugin also
# references the optional Chinese/Devanagari/Japanese/Korean models.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Google sign-in (Credential Manager) is loaded by reflection; keep it from R8.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** {
  *;
}
