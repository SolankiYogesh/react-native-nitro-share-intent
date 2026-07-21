package nitroshareintent.example

import android.content.Intent
import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate

class MainActivity : ReactActivity() {

  /**
   * Returns the name of the main component registered from JavaScript. This is used to schedule
   * rendering of the component.
   */
  override fun getMainComponentName(): String = "NitroShareIntentExample"

  /**
   * Returns the instance of the [ReactActivityDelegate]. We use [DefaultReactActivityDelegate]
   * which allows you to enable New Architecture with a single boolean flags [fabricEnabled]
   */
  override fun createReactActivityDelegate(): ReactActivityDelegate =
      DefaultReactActivityDelegate(this, mainComponentName, fabricEnabled)

  /**
   * Because this Activity uses `launchMode="singleTask"` (required so re-sharing to an
   * already-running instance of the app doesn't spawn a duplicate Activity), Android delivers
   * subsequent share intents through `onNewIntent` instead of creating a new Activity/Intent.
   *
   * `setIntent(intent)` updates `Activity.getIntent()` so a later `getInitialShare()` call sees
   * the freshest intent instead of the stale one from the original launch. `super.onNewIntent()`
   * forwards the intent through React Native's `ReactActivity`/`ReactInstanceManager`, which
   * dispatches it to every registered `ActivityEventListener#onNewIntent` - including the
   * `NitroShareIntent` native module, which already registers itself as one. Without this
   * override (or if a consumer app overrides `onNewIntent` for its own purposes without calling
   * `super`/forwarding to the instance manager), re-shares to an already-running app would never
   * reach JS. Any consumer app using `singleTask`/`singleTop` launch modes needs this same
   * override - see the README's Android setup section.
   */
  override fun onNewIntent(intent: Intent) {
    setIntent(intent)
    super.onNewIntent(intent)
  }
}
