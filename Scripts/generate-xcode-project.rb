#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "pathname"
require "xcodeproj"

root = Pathname(__dir__).join("..").expand_path
project_path = root.join("UsageBeacon.xcodeproj")

FileUtils.rm_rf(project_path)
project = Xcodeproj::Project.new(project_path.to_s)
project.root_object.attributes["LastSwiftUpdateCheck"] = "1610"
project.root_object.attributes["LastUpgradeCheck"] = "1610"

sources_group = project.main_group.new_group("Sources", "Sources")
resources_group = project.main_group.new_group("Resources", "Resources")
config_group = project.main_group.new_group("Config", "Config")
products_group = project.products_group

def add_swift_sources(group, target, directory)
  Dir.glob(directory.join("**", "*.swift").to_s).sort.each do |source|
    relative = Pathname(source).relative_path_from(directory).to_s
    reference = group.new_file(relative)
    target.source_build_phase.add_file_reference(reference)
  end
end

def add_framework(project, target, name)
  framework = project.frameworks_group.files.find { |file| file.path == "System/Library/Frameworks/#{name}.framework" }
  framework ||= project.frameworks_group.new_file("System/Library/Frameworks/#{name}.framework")
  framework.source_tree = "SDKROOT"
  target.frameworks_build_phase.add_file_reference(framework)
end

def configure_build_settings(target, values)
  target.build_configurations.each do |configuration|
    configuration.build_settings.merge!(values)
    configuration.build_settings["ONLY_ACTIVE_ARCH"] = "YES" if configuration.name == "Debug"
    configuration.build_settings["ONLY_ACTIVE_ARCH"] = "NO" if configuration.name == "Release"
  end
end

shared_target = project.new_target(:static_library, "UsageBeaconShared", :osx, "14.0")
app_target = project.new_target(:application, "UsageBeacon", :osx, "14.0")
widget_target = project.new_target(:app_extension, "UsageBeaconWidget", :osx, "14.0")

shared_group = sources_group.new_group("UsageBeaconShared", "UsageBeaconShared")
app_group = sources_group.new_group("UsageBeaconApp", "UsageBeaconApp")
widget_group = sources_group.new_group("UsageBeaconWidget", "UsageBeaconWidget")

add_swift_sources(shared_group, shared_target, root.join("Sources", "UsageBeaconShared"))
add_swift_sources(app_group, app_target, root.join("Sources", "UsageBeaconApp"))
add_swift_sources(widget_group, widget_target, root.join("Sources", "UsageBeaconWidget"))

app_target.add_dependency(shared_target)
app_target.add_dependency(widget_target)
widget_target.add_dependency(shared_target)
app_target.frameworks_build_phase.add_file_reference(shared_target.product_reference)
widget_target.frameworks_build_phase.add_file_reference(shared_target.product_reference)

embed_extensions = app_target.new_copy_files_build_phase("Embed App Extensions")
embed_extensions.symbol_dst_subfolder_spec = :plug_ins
embedded_widget = embed_extensions.add_file_reference(widget_target.product_reference)
embedded_widget.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }

%w[AppKit Carbon EventKit Security SwiftUI WebKit WidgetKit].each do |framework|
  add_framework(project, app_target, framework)
end
%w[SwiftUI WidgetKit].each do |framework|
  add_framework(project, widget_target, framework)
end

app_icon = resources_group.new_file("AppIcon.icns")
app_target.resources_build_phase.add_file_reference(app_icon)
resources_group.new_file("UsageBeacon-Info.plist")
resources_group.new_file("UsageBeaconWidget-Info.plist")
resources_group.new_file("UsageBeacon.entitlements")
resources_group.new_file("UsageBeaconWidget.entitlements")

version_configuration = config_group.new_file("Version.xcconfig")
project.targets.each do |target|
  target.build_configurations.each do |configuration|
    configuration.base_configuration_reference = version_configuration
  end
end

sparkle_package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
sparkle_package.repositoryURL = "https://github.com/sparkle-project/Sparkle"
sparkle_package.requirement = {
  "kind" => "exactVersion",
  "version" => "2.9.6"
}
project.root_object.package_references << sparkle_package

sparkle_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
sparkle_product.package = sparkle_package
sparkle_product.product_name = "Sparkle"
app_target.package_product_dependencies << sparkle_product

sparkle_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
sparkle_build_file.product_ref = sparkle_product
app_target.frameworks_build_phase.files << sparkle_build_file

common_settings = {
  "CLANG_ENABLE_MODULES" => "YES",
  "CODE_SIGN_STYLE" => "Manual",
  "DEVELOPMENT_TEAM" => "Y3XM9Q3AZT",
  "ENABLE_HARDENED_RUNTIME" => "YES",
  "MACOSX_DEPLOYMENT_TARGET" => "14.0",
  "SWIFT_VERSION" => "6.0"
}

configure_build_settings(shared_target, common_settings.merge(
  "DEFINES_MODULE" => "YES",
  "PRODUCT_NAME" => "UsageBeaconShared",
  "SKIP_INSTALL" => "YES"
))

configure_build_settings(app_target, common_settings.merge(
  "CODE_SIGN_ENTITLEMENTS" => "Resources/UsageBeacon.entitlements",
  "INFOPLIST_FILE" => "Resources/UsageBeacon-Info.plist",
  "LD_RUNPATH_SEARCH_PATHS" => "$(inherited) @executable_path/../Frameworks",
  "PRODUCT_BUNDLE_IDENTIFIER" => "com.rekindle.usagebeacon",
  "PRODUCT_MODULE_NAME" => "UsageBeaconApp",
  "PRODUCT_NAME" => "UsageBeacon",
  "SKIP_INSTALL" => "NO"
))

configure_build_settings(widget_target, common_settings.merge(
  "APPLICATION_EXTENSION_API_ONLY" => "YES",
  "CODE_SIGN_ENTITLEMENTS" => "Resources/UsageBeaconWidget.entitlements",
  "INFOPLIST_FILE" => "Resources/UsageBeaconWidget-Info.plist",
  "LD_RUNPATH_SEARCH_PATHS" => "$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks",
  "PRODUCT_BUNDLE_IDENTIFIER" => "com.rekindle.usagebeacon.widget",
  "PRODUCT_NAME" => "UsageBeaconWidget",
  "SKIP_INSTALL" => "YES"
))

project.targets.each do |target|
  target.product_reference.move(products_group) unless target.product_reference.parent == products_group
end

project.save
puts "Generated #{project_path}"
