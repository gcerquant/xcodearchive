#!/usr/bin/env ruby
#  xcodearchive.rb
#
#  Created by Guillaume Cerquant on 2011-11-16.
#  Copyright 2011 MacMation. All rights reserved.
#

# What is this?
#   xcodebuild builds an Xcode project
#   xcodearchive archive an Xcode project... wait! Apple did not ship an xcodearchive command
#   This script intends to substitute to it.
#   It allows you to generate an ipa via the command line
#

# CHANGELOG
#   0.2 - Now reads the iPhone developper identity from the Xcode project
#   0.3 - Option to set the developper identity - Read the application version number and use it in the filename of zip dSYM symbols
#   0.4 - Build the project in a temporary directory
#   1.0 - When in verbose mode, displays the logs output by Xcode
#   1.0.1 - Can now use the --project option using a relative or absolute path
#   1.0.2 - Status code return real errors

# CREDITS
#   Thank you to Vincent Daubry for his discovery of the xcrun command, which greatly simplified this script
#   http://blog.octo.com/automatiser-le-deploiement-over-the-air/
#
#   Thank you to Yannick Cadin. Some of his code to detect the SDK version of an Xcode project has been used and adapted to
#   detect the iPhone developper identity
#   http://diablotin.info/

# TODO
#  Know bugs
#   - Running the shell commands with the backticks, we loose the stderr output
#   - handle the case where the product name is different from target name

#
# New Features
#   - generate a manifest plist file (equivalent of the checkbox "Save for Enterprise" in Xcode)
#   - be able to force a sdk version
#   - print the information about the project (base sdk, deployement target, size of ipa)


require 'optparse'
require 'open3'
require 'tmpdir'
require 'pathname'

@version_number="1.0.2"

# Use xcode-select -switch <xcode_folder_path> to set your Xcode folder path
XCODEBUILD="/usr/bin/xcodebuild"
BZR="/usr/local/bin/bzr"
SVN="/usr/bin/svn"
PLISTBUDDY = "/usr/libexec/PlistBuddy"

ERROR_NO_XCODE_PROJECT_FOUND=2
ERROR_MULTIPLE_XCODE_PROJECTS_FOUND=3
ERROR_DID_NOT_FOUND_RELEASE_CONFIGURATION=4
ERROR_CLEAN=5
ERROR_BUILD=6
ERROR_CODESIGN=7
ERROR_DID_NOT_FOUND_DSYM_FILE=8


def parse_options
  @options = {}

  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: xcodearchive [OPTIONS]"

    opts.on( '', '--version', 'Show version number' ) do
      puts "Version #{@version_number}"
      exit
    end


    @options[:verbose] = false
    opts.on( '-v', '--verbose', 'Output more information' ) do
      @options[:verbose] = true
    end

    @options[:growl] = false
    opts.on( '-g', '--growl', 'Show growl alerts to inform about progress of the build' ) do
      @options[:growl] = true
    end

    @options[:no_symbol] = false
    opts.on( '-n', '--do_not_keep_dsym_symbols', 'Do not keep the dSYM symbols' ) do
      @options[:no_symbol] = true
    end

    @options[:show] = false
    opts.on( '-s', '--show', 'Show archive in Finder once created' ) do
      @options[:show] = true
    end

    @options[:clean_before_building] = false
    opts.on( '-c', '--clean', 'Do a clean before building the Xcode project' ) do
      @options[:clean_before_building] = true
    end


    @options[:ipa_export_path] = nil
    opts.on( '-o', '--ipa_export_path FOLDER', 'Set the path of the folder where the ipa will be saved. Default is \'~/Desktop\'' ) do |ipa_export_folder_path|
      @options[:ipa_export_path] = ipa_export_folder_path
    end

    @options[:developper_identity] = nil
    opts.on( '-i', '--developper_identity DEVELOPPER_IDENTITY', 'Force the developper identity value' ) do |developper_identity|
      @options[:developper_identity] = developper_identity
    end

    @options[:mobile_provision] = nil
    opts.on( '-m', '--mobile_provision MOBILE_PROVISION_NAME', 'Force the mobile provision file to use' ) do |mobile_provision|
      @options[:mobile_provision] = mobile_provision
    end

    @options[:archive_from_app_path] = nil
    opts.on( '-a', '--archive_from_app_path APP_PATH', 'Create ipa from an existing App path.' ) do |app_path|
      @options[:archive_from_app_path] = app_path
    end

    @options[:project] = nil
    opts.on( '-p', '--project PROJECT', 'Specifiy xcode project') do |xcodeproject_file|
      @options[:project] = xcodeproject_file
      #todo : WILL not work with a full file path
    end

    # todo : generate a manifest plist file (will be useful when we will be parsing the version number)

    opts.on( '-h', '--help', 'Display this screen' ) do
      puts opts

      puts "\n\n\nExamples:\n
xcodearchive                                => Build the Xcode project of the current folder, generate an archive (ipa), and create a zip with the dSYM symbols
xcodearchive -n                             => Same as above, but do not keep the symbols
xcodearchive -o ~/Documents/my_archives -s  => Save the ipa in the given folder, and reveal it in the Finder"

      exit
    end
  end

  optparse.parse!

end


def xcode_project_file_path
  return File.expand_path(@options[:project]) if (@options[:project])

  all_xcode_projs = Dir.glob("*.xcodeproj")
  if (all_xcode_projs.count == 0)
    puts "Error: 0 xcodeprojects found"
    exit ERROR_NO_XCODE_PROJECT_FOUND
  end

  if (all_xcode_projs.count != 1)
    puts "Error: The directory #{Dir.pwd} contains #{all_xcode_projs.count} projects (file with the extension .xcodeproj). Specify the project to use with the --project option."
    exit ERROR_MULTIPLE_XCODE_PROJECTS_FOUND
  end

  File.expand_path("./#{all_xcode_projs[0]}")
end

# def sdk_version
#   "iphoneos5.0" #TODO - Be able to force a sdk version
#   Will be useful to compile with an older sdk, to make sure no api is used in a version where they do not exists
# end


def project_name
  return File.basename(@options[:archive_from_app_path], '.app') if @options[:archive_from_app_path]
  File.basename( xcode_project_file_path(), ".xcodeproj")
end

def target_name

end

def archive_name

end

@temp_build_directory = nil
def path_of_temp_directory_where_to_build
  return @temp_build_directory if @temp_build_directory
  @temp_build_directory = Dir.mktmpdir
  return @temp_build_directory
end

def path_of_directory_where_to_export
  if @options[:ipa_export_path]
    return File.expand_path(@options[:ipa_export_path])
  else
    return "#{ENV['HOME']}/Desktop/"
  end
end

def path_of_created_ipa
  "#{path_of_directory_where_to_export}/#{project_name}.ipa"
end

def developper_identity
  if @options[:developper_identity]
    return @options[:developper_identity]
  end

  root_id = `#{PLISTBUDDY} -c Print\\ :rootObject #{xcode_project_file_path}/project.pbxproj`.chop
  build_configurations_ID = `#{PLISTBUDDY} -c Print\\ :objects:#{root_id}:buildConfigurationList #{xcode_project_file_path}/project.pbxproj`.chop

  # TODO: Here we are using an hard coded index
  release_id = `#{PLISTBUDDY} -c Print\\ :objects:#{build_configurations_ID}:buildConfigurations:1 #{xcode_project_file_path}/project.pbxproj`.chop

  name_of_configuration = `#{PLISTBUDDY} -c Print\\ :objects:#{release_id}:name #{xcode_project_file_path}/project.pbxproj`.chop
  if (name_of_configuration != "Release")
    puts "Did not found expected configuration - got '#{name_of_configuration}' ; expected 'Release'"
    exit ERROR_DID_NOT_FOUND_RELEASE_CONFIGURATION
  end

  # all = `#{PLISTBUDDY} -c Print\\ :objects:#{release_id}:buildSettings #{xcode_project_file_path}/project.pbxproj`
  # puts "all #{all}"

  identity = `#{PLISTBUDDY} -c Print\\ :objects:#{release_id}:buildSettings:CODE_SIGN_IDENTITY[sdk=iphoneos*] #{xcode_project_file_path}/project.pbxproj`.chop

  identity
end

def mobile_provisionning_profile_path
  "#{path_of_builded_application}/embedded.mobileprovision"
end


def show_all_parameters
  puts "Working with #{project_name || xcode_project_file_path}"
  puts "\nPerforming task with options: #{@options.inspect}"
  # puts "SDK Version: #{sdk_version()}"
  # TODO print everything useful here
end

def verbose
  @options[:verbose]
end


def mobileprovision_command_installed
  return system("mobileprovision --version")
end


def path_of_builded_application
  if @options[:archive_from_app_path]
    File.expand_path(@options[:archive_from_app_path])
  else
    "#{path_of_temp_directory_where_to_build}/Release-iphoneos/#{project_name}.app"
  end
end

def archive_xcode_project
  if (verbose)
    if (mobileprovision_command_installed)
      puts "\nmobileprovision file info:"
      puts `mobileprovision #{mobile_provisionning_profile_path}`
      puts "\n\n"
    else
      puts "mobileprovision command not found. Unable to give details about the provisionningprofile."
    end

    puts "\nDevelopper identity: #{developper_identity}"
    puts "\nApplication version number: #{application_version_number(path_of_builded_application)}"
  end

  growl_alert("Archiving", "Identity: #{developper_identity}\nmobileprovision: `mobileprovision #{mobile_provisionning_profile_path}`")

  mobile_provision_path = @options[:mobile_provision] || mobile_provisionning_profile_path
  sign_identity_opt = "--sign \"#{developper_identity}\"" if developper_identity
  xcrun_command = "/usr/bin/xcrun -sdk iphoneos PackageApplication -v \"#{path_of_builded_application}\" -o \"#{path_of_created_ipa}\" #{sign_identity_opt} --embed \"#{mobile_provision_path}\""
  puts "Archiving:\n #{xcrun_command}\n\n\n" if verbose
  output = `#{xcrun_command}`

  if (0 != $?.to_i)
    puts "Error in xcrun: #{$?.to_s}"
    puts "#{output}"
    exit ERROR_CODESIGN
  end

  puts "\nArchiving succeedeed: IPA created"
  puts "IPA file saved to: '#{path_of_created_ipa}'" if verbose

  reveal_file_in_finder(path_of_created_ipa) if @options[:show]

end

def build_xcode_project
  return if @options[:archive_from_app_path]

  puts "Using temporary path for build: #{path_of_temp_directory_where_to_build}" if verbose

  build_command="#{XCODEBUILD} -project #{xcode_project_file_path()} SYMROOT=\"#{path_of_temp_directory_where_to_build}\""
  build_command += " PROVISIONING_PROFILE=#{@options[:mobile_provision]}" if @options[:mobile_provision]
  puts "Building:\n#{build_command}" if verbose
  growl_alert("Building", "Building xCode project #{xcode_project_file_path}")

  if @options[:clean_before_building]
    puts "Cleaning Xcode project" if verbose
    `#{XCODEBUILD} -project #{xcode_project_file_path()} clean`
    if (0 != $?.to_i)
      puts "Error in xcodebuild (clean): #{$?.to_s}"
      exit ERROR_CLEAN
    end
  end

  output = `#{build_command}`

  if (0 != $?.to_i)
    puts "Error in xcodebuild: #{$?.to_s}"
    puts "#{output}"
    exit ERROR_BUILD
  end
end


def application_version_number(application_path)
  # product_version_number=`#{PLISTBUDDY} "#{path_of_builded_application}/Regions-Info.plist" -c Print\\ :CFBundleVersion`.chop
  product_version_number=`#{PLISTBUDDY} "#{path_of_builded_application}/Info.plist" -c Print\\ :CFBundleVersion`.chop
  product_version_number=`#{PLISTBUDDY} "#{path_of_builded_application}/#{project_name}-Info.plist" -c Print\\ :CFBundleVersion`.chop if (nil == product_version_number)

  product_version_number
end


def create_zip_archive_of_the_symbols
  return if (@options[:no_symbol])

  puts "Archiving the dSYM symbols"

  date=`date '+%Y%m%d_%H'h'%M'`.chop
  filename_for_dsym_symbols_archive="#{project_name}_version_#{application_version_number(path_of_builded_application)}_#{date}_dSYM_symbols.zip"
  filepath_for_dsym_symbols_archive="#{path_of_directory_where_to_export}/#{filename_for_dsym_symbols_archive}"

  growl_alert("dSYM symbols", "Archiving the dSYM symbols into #{filepath_for_dsym_symbols_archive}")


  filename_of_generated_symbols="#{project_name}.app.dSYM"

  unless File.exists? "#{path_of_temp_directory_where_to_build}/Release-iphoneos/filename_of_generated_symbols"
    puts "Error: Could not find your dSYM file."
    puts 'Try again with the --no_symbol option.'
    exit ERROR_DID_NOT_FOUND_DSYM_FILE
  end

  # If we don't want to have the archive contain hierarchy, we need to cd first
  Dir.chdir "#{path_of_temp_directory_where_to_build}/Release-iphoneos" do
    `zip -r -T -y "#{filepath_for_dsym_symbols_archive}" "#{filename_of_generated_symbols}"`

    # TODO: Check for error here when zipping
  end

  puts "dSYM symbols archived into #{filepath_for_dsym_symbols_archive}"

end

def growl_alert(title, message)
  if (@options[:growl])
    growlnotify="/usr/local/bin/growlnotify" # Edit this if you installed growlnotify in a different place

    if (File.executable?(growlnotify))
      `#{growlnotify} "#{title}" -m "#{message}" -d archivingBubble`
    else
      puts "Did not found growlnotify command"
    end
  end
end


def reveal_file_in_finder(file_path)
  applescript_command = "tell application \"Finder\"\nreveal POSIX file \"#{file_path}\"\n activate\nend tell"
  `osascript -e '#{applescript_command}'`
end


parse_options

show_all_parameters if verbose

build_xcode_project
archive_xcode_project
create_zip_archive_of_the_symbols
