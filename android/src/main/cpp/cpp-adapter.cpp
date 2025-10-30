#include <jni.h>
#include "nitroshareintentOnLoad.hpp"

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  return margelo::nitro::nitroshareintent::initialize(vm);
}
