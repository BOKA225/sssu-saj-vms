// À copier dans android/app/src/main/kotlin/ci/sssusaj/sssu_mobile/MainActivity.kt
// après `flutter create --org ci.sssusaj --platforms=android .`
package ci.sssusaj.sssu_mobile

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity est requis par flutter_secure_storage / mobile_scanner.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Interdit les captures d'écran et masque l'aperçu dans les applications récentes :
        // les écrans affichent des données médicales de mineurs.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }
}
