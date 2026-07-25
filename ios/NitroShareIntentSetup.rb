# NitroShareIntentSetup
#
# Creates and embeds the iOS Share Extension target during `pod install`, so a
# consumer never has to open Xcode or edit anything under `ios/`.
#
# This is invoked from NitroShareIntent.podspec. A podspec is plain Ruby
# evaluated in-process by CocoaPods, and CocoaPods already depends on
# Xcodeproj - so the target can be created here and it survives the later
# integration pass that re-opens and saves the user project.
#
# Everything is configured from the app's package.json (no ios/ edits):
#
#   "nitroShareIntent": {
#     "ios": {
#       "enabled": true,                       // set false to opt out entirely
#       "appGroup": "group.com.acme.app",      // default: group.<bundleId>.nitroshareintent
#       "extensionName": "NitroShareExtension",
#       "openHostApp": true,                   // foreground the app after a share
#       "activation": {                        // what the share sheet offers us for
#         "images": 10, "movies": 10, "text": true, "urls": 1, "files": 10
#       }
#     }
#   }

require 'json'

module NitroShareIntentSetup
  AUTHOR = 'Yogesh Solanki'.freeze
  DEFAULT_EXTENSION_NAME = 'NitroShareExtension'.freeze
  MANAGED_MARKER = 'NitroShareIntentManaged'.freeze

  module_function

  def install!(pod_root)
    require 'xcodeproj'

    root = Pod::Config.instance.installation_root.to_s
    return if root.nil? || root.empty?

    config = read_config(root)
    return if config['enabled'] == false

    project_path = find_user_project(root)
    return if project_path.nil?

    project = Xcodeproj::Project.open(project_path)
    host = project.targets.find { |t| t.product_type == 'com.apple.product-type.application' }
    return if host.nil?

    host_settings = host.build_configurations.first.build_settings
    bundle_id = host_settings['PRODUCT_BUNDLE_IDENTIFIER'].to_s

    if bundle_id.empty? || bundle_id.include?('$(')
      Pod::UI.warn "[NitroShareIntent] Host bundle identifier is '#{bundle_id}' and can't be " \
                   'resolved here - set nitroShareIntent.ios.appGroup in package.json to enable ' \
                   'the Share Extension.'
      return if config['appGroup'].to_s.empty?
    end

    name = (config['extensionName'] || DEFAULT_EXTENSION_NAME).to_s
    app_group = (config['appGroup'] || "group.#{bundle_id}.nitroshareintent").to_s
    extension_bundle_id = "#{bundle_id}.#{name}"
    deployment = host_settings['IPHONEOS_DEPLOYMENT_TARGET'] || '15.1'

    created = project.targets.none? { |t| t.name == name }
    target = project.targets.find { |t| t.name == name } ||
             project.new_target(:app_extension, name, :ios, deployment)

    group_dir = File.join(root, name)
    FileUtils.mkdir_p(group_dir)

    write_extension_plist(File.join(group_dir, 'Info.plist'), name, app_group, config,
                          host_url_scheme(host_settings, root))
    write_entitlements(File.join(group_dir, "#{name}.entitlements"), app_group)

    configure_target(target, name, extension_bundle_id, deployment, host_settings)
    attach_sources(project, target, pod_root, name)
    embed_in_host(host, target)
    grant_host_app_group(host, host_settings, root, app_group)

    project.save

    announce(created, name, app_group)
  rescue LoadError, StandardError => e
    # Never take a consumer's `pod install` down over this - the app itself
    # still builds and works, just without the auto-generated extension.
    Pod::UI.warn "[NitroShareIntent] Share Extension setup skipped: #{e.class}: #{e.message}"
  end

  def read_config(root)
    package_json = File.expand_path(File.join(root, '..', 'package.json'))
    return {} unless File.exist?(package_json)

    parsed = JSON.parse(File.read(package_json))
    ((parsed['nitroShareIntent'] || {})['ios'] || {})
  rescue JSON::ParserError
    {}
  end

  def find_user_project(root)
    candidates = Dir.glob(File.join(root, '*.xcodeproj')).reject { |p| p.include?('Pods.xcodeproj') }
    if candidates.length > 1
      Pod::UI.warn "[NitroShareIntent] Multiple .xcodeproj files found in #{root}; using " \
                   "#{File.basename(candidates.first)}."
    end
    candidates.first
  end

  # The extension foregrounds the host app through its custom URL scheme; if
  # the app doesn't declare one, the share is still collected the next time
  # the app becomes active.
  def host_url_scheme(host_settings, root)
    plist_path = host_settings['INFOPLIST_FILE'].to_s
    return nil if plist_path.empty?

    resolved = File.expand_path(File.join(root, plist_path.gsub('$(SRCROOT)', '.')))
    return nil unless File.exist?(resolved)

    plist = Xcodeproj::Plist.read_from_path(resolved)
    types = plist['CFBundleURLTypes']
    return nil unless types.is_a?(Array)

    types.map { |t| (t['CFBundleURLSchemes'] || []).first }.compact.first
  rescue StandardError
    nil
  end

  def write_extension_plist(path, name, app_group, config, url_scheme)
    activation = config['activation'] || {}
    rule = {
      'NSExtensionActivationSupportsImageWithMaxCount' => activation.fetch('images', 10),
      'NSExtensionActivationSupportsMovieWithMaxCount' => activation.fetch('movies', 10),
      'NSExtensionActivationSupportsFileWithMaxCount' => activation.fetch('files', 10),
      'NSExtensionActivationSupportsText' => activation.fetch('text', true),
      'NSExtensionActivationSupportsWebURLWithMaxCount' => activation.fetch('urls', 1)
    }

    plist = {
      'CFBundleName' => '$(PRODUCT_NAME)',
      'CFBundleDisplayName' => '$(PRODUCT_NAME)',
      'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)',
      'CFBundleExecutable' => '$(EXECUTABLE_NAME)',
      'CFBundlePackageType' => '$(PRODUCT_BUNDLE_PACKAGE_TYPE)',
      'CFBundleShortVersionString' => '$(MARKETING_VERSION)',
      'CFBundleVersion' => '$(CURRENT_PROJECT_VERSION)',
      MANAGED_MARKER => true,
      'NitroShareIntentAppGroup' => app_group,
      'NitroShareIntentOpenHostApp' => config.fetch('openHostApp', true),
      'NSExtension' => {
        'NSExtensionPointIdentifier' => 'com.apple.share-services',
        # The principal class ships inside the pod, so the generated target
        # holds no consumer source at all.
        'NSExtensionPrincipalClass' => '$(PRODUCT_MODULE_NAME).NitroShareViewController',
        'NSExtensionAttributes' => { 'NSExtensionActivationRule' => rule }
      }
    }
    plist['NitroShareIntentHostURLScheme'] = url_scheme if url_scheme

    Xcodeproj::Plist.write_to_path(plist, path)
  end

  def write_entitlements(path, app_group)
    Xcodeproj::Plist.write_to_path({ 'com.apple.security.application-groups' => [app_group] }, path)
  end

  def configure_target(target, name, bundle_id, deployment, host_settings)
    target.build_configurations.each do |cfg|
      cfg.build_settings.merge!(
        'PRODUCT_NAME' => name,
        'PRODUCT_BUNDLE_IDENTIFIER' => bundle_id,
        'INFOPLIST_FILE' => "#{name}/Info.plist",
        'CODE_SIGN_ENTITLEMENTS' => "#{name}/#{name}.entitlements",
        'IPHONEOS_DEPLOYMENT_TARGET' => deployment,
        'SWIFT_VERSION' => host_settings['SWIFT_VERSION'] || '5.0',
        'TARGETED_DEVICE_FAMILY' => '1,2',
        'GENERATE_INFOPLIST_FILE' => 'NO',
        'SKIP_INSTALL' => 'YES',
        # Without these the Info.plist's $(MARKETING_VERSION)/
        # $(CURRENT_PROJECT_VERSION) expand to empty, the version keys are
        # dropped, and installing fails with "Invalid placeholder attributes".
        'MARKETING_VERSION' => host_settings['MARKETING_VERSION'] || '1.0',
        'CURRENT_PROJECT_VERSION' => host_settings['CURRENT_PROJECT_VERSION'] || '1',
        'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
      )
      cfg.build_settings['DEVELOPMENT_TEAM'] = host_settings['DEVELOPMENT_TEAM'] if host_settings['DEVELOPMENT_TEAM']
      cfg.build_settings['CODE_SIGN_STYLE'] = host_settings['CODE_SIGN_STYLE'] || 'Automatic'
    end
  end

  # References the pod's own ShareViewController rather than copying it, so a
  # package upgrade ships the new implementation without re-running anything.
  def attach_sources(project, target, pod_root, name)
    source = File.join(pod_root, 'ios', 'ShareExtension', 'NitroShareViewController.swift')
    return unless File.exist?(source)

    already = target.source_build_phase.files_references.any? do |ref|
      ref.real_path.to_s == source
    end
    return if already

    group = project.main_group.find_subpath(name, true)
    group.set_source_tree('SOURCE_ROOT')
    ref = group.new_file(source)
    target.source_build_phase.add_file_reference(ref)
  end

  def embed_in_host(host, target)
    phase = host.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
    if phase.nil?
      phase = host.new_copy_files_build_phase('Embed Foundation Extensions')
      phase.symbol_dst_subfolder_spec = :plug_ins
    end

    already = phase.files_references.any? { |ref| ref.uuid == target.product_reference.uuid }
    phase.add_file_reference(target.product_reference) unless already

    host.add_dependency(target) unless host.dependencies.any? { |d| d.target&.uuid == target.uuid }
  end

  # The host app needs the same App Group to read what the extension wrote,
  # plus the id in its Info.plist so NitroShareIntent.swift can find it.
  def grant_host_app_group(host, host_settings, root, app_group)
    entitlements_path = host_settings['CODE_SIGN_ENTITLEMENTS'].to_s

    if entitlements_path.empty?
      entitlements_path = "#{host.name}/#{host.name}.entitlements"
      host.build_configurations.each do |cfg|
        cfg.build_settings['CODE_SIGN_ENTITLEMENTS'] = entitlements_path
      end
    end

    absolute = File.join(root, entitlements_path)
    FileUtils.mkdir_p(File.dirname(absolute))
    entitlements = File.exist?(absolute) ? Xcodeproj::Plist.read_from_path(absolute) : {}
    groups = entitlements['com.apple.security.application-groups'] || []
    unless groups.include?(app_group)
      entitlements['com.apple.security.application-groups'] = groups + [app_group]
      Xcodeproj::Plist.write_to_path(entitlements, absolute)
    end

    plist_path = host_settings['INFOPLIST_FILE'].to_s
    return if plist_path.empty?

    resolved = File.expand_path(File.join(root, plist_path.gsub('$(SRCROOT)', '.')))
    return unless File.exist?(resolved)

    plist = Xcodeproj::Plist.read_from_path(resolved)
    return if plist['NitroShareIntentAppGroup'] == app_group

    plist['NitroShareIntentAppGroup'] = app_group
    Xcodeproj::Plist.write_to_path(plist, resolved)
  end

  def announce(created, name, app_group)
    Pod::UI.puts ''
    Pod::UI.puts "  ✨ NitroShareIntent — thanks for installing! Made with 💛 by #{AUTHOR}".green
    if created
      Pod::UI.puts "     Created Share Extension target '#{name}' and embedded it in your app.".green
    else
      Pod::UI.puts "     Share Extension target '#{name}' is up to date.".green
    end
    Pod::UI.puts "     App Group: #{app_group}"
    Pod::UI.puts '     Enable the App Groups capability for both targets in Signing & Capabilities.'
    Pod::UI.puts '     Opt out any time: "nitroShareIntent": { "ios": { "enabled": false } } in package.json'
    Pod::UI.puts ''
  end
end
