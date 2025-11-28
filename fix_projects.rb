#!/usr/bin/env ruby
require 'xcodeproj'

# Fix Host project
puts "Fixing ScreenToScreenHost project..."
host_project = Xcodeproj::Project.open('ScreenToScreenHost/ScreenToScreenHost.xcodeproj')
host_target = host_project.targets.find { |t| t.name == 'ScreenToScreenHost' }

# Find the Services group
host_sources_group = host_project.main_group.find_subpath('Sources', false)
host_services_group = host_sources_group.find_subpath('Services', false)

# Add service files to Host
service_files = [
  'InputController.swift',
  'ScreenCaptureService.swift',
  'SignalingServer.swift',
  'WebRTCManager.swift'
]

service_files.each do |filename|
  file_path = "Sources/Services/#{filename}"
  # Check if already added
  existing = host_services_group.files.find { |f| f.path == file_path || f.name == filename }
  if existing.nil?
    file_ref = host_services_group.new_file(file_path)
    host_target.source_build_phase.add_file_reference(file_ref)
    puts "  Added #{filename}"
  else
    puts "  #{filename} already exists"
  end
end

host_project.save
puts "Host project saved.\n\n"

# Fix Client project
puts "Fixing ScreenToScreenClient project..."
client_project = Xcodeproj::Project.open('ScreenToScreenClient/ScreenToScreenClient.xcodeproj')
client_target = client_project.targets.find { |t| t.name == 'ScreenToScreenClient' }

client_sources_group = client_project.main_group.find_subpath('Sources', false)

# Define all the groups and their files for the client
client_files = {
  'Services' => [
    'BonjourBrowser.swift',
    'SignalingClient.swift',
    'WebRTCClient.swift'
  ],
  'Views' => [
    'HostListView.swift',
    'RemoteSessionView.swift',
    'SpecialKeyboardView.swift',
    'VideoRenderView.swift',
    'GestureOverlayView.swift'
  ],
  'Models' => [
    'HostInfo.swift'
  ],
  'Gestures' => [
    'CursorState.swift',
    'GestureController.swift'
  ]
}

client_files.each do |group_name, files|
  group = client_sources_group.find_subpath(group_name, false)
  if group.nil?
    group = client_sources_group.new_group(group_name)
    puts "  Created group: #{group_name}"
  end

  files.each do |filename|
    file_path = "Sources/#{group_name}/#{filename}"
    existing = group.files.find { |f| f.path == file_path || f.name == filename }
    if existing.nil?
      file_ref = group.new_file(file_path)
      client_target.source_build_phase.add_file_reference(file_ref)
      puts "  Added #{group_name}/#{filename}"
    else
      puts "  #{group_name}/#{filename} already exists"
    end
  end
end

client_project.save
puts "Client project saved."

puts "\nDone! Please close and reopen both Xcode projects."
