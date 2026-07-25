require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "NitroShareIntent"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/SolankiYogesh/react-native-nitro-share-intent.git", :tag => "#{s.version}" }


  s.source_files = [
    "ios/**/*.{swift}",
    "ios/**/*.{m,mm}",
    "cpp/**/*.{hpp,cpp}",
  ]

  # The Share Extension's principal class is compiled into the generated
  # extension target (see ios/NitroShareIntentSetup.rb), not into the app.
  s.exclude_files = "ios/ShareExtension/**/*"

  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'

  load 'nitrogen/generated/ios/NitroShareIntent+autolinking.rb'
  add_nitrogen_files(s)

  # Creates + embeds the iOS Share Extension target in the consuming app, so
  # `pod install` is the whole setup - no Xcode target, no native code, no
  # Podfile changes. Opt out with
  # `"nitroShareIntent": { "ios": { "enabled": false } }` in the app's
  # package.json.
  require File.join(__dir__, 'ios', 'NitroShareIntentSetup.rb')
  NitroShareIntentSetup.install!(__dir__)

  install_modules_dependencies(s)
end
