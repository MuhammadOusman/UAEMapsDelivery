# Add project specific ProGuard rules here.
# This fixes R8 warnings for the HERE SDK resource references.

-dontwarn com.here.sdk.R$id
-dontwarn com.here.sdk.R$layout
-dontwarn com.here.sdk.R$string
-dontwarn com.here.sdk.R$styleable
