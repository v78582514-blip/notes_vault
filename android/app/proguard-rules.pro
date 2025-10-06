# Минимальный набор правил (можно расширять по мере необходимости)
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class androidx.lifecycle.DefaultLifecycleObserver
-dontwarn java.lang.invoke.*
-dontwarn org.codehaus.mojo.animal_sniffer.*
