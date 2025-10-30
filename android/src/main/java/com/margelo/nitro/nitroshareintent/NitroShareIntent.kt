package com.margelo.nitro.nitroshareintent
  
import com.facebook.proguard.annotations.DoNotStrip

@DoNotStrip
class NitroShareIntent : HybridNitroShareIntentSpec() {
  override fun multiply(a: Double, b: Double): Double {
    return a * b
  }
}
