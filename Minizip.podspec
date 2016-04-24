Pod::Spec.new do |s|
  s.name     = 'Minizip'
  s.version  = '1.2.0'
  s.license  =  { :type => 'MIT', :file => 'LICENSE' }
  s.summary  = 'Minizip framework wrapper for iOS, OSX, tvOS, and watchOS.'
  s.homepage = 'https://github.com/dexman/Minizip'
  s.author   = { 'Arthur Dexter' => "adexter@dexman.net" }
  s.source   = { :git => 'https://github.com/dexman/Minizip.git', :tag => '1.2.0' }

  s.platform = :ios, '8.0'
  #s.ios.deployment_target = '8.0'
  #s.osx.deployment_target = '10.11'
  #s.watchos.deployment_target = '2.0'
  #s.tvos.deployment_target = '9.0'

  s.requires_arc = true

  s.preserve_path = 'Minizip/*'
  s.source_files =  [ "Minizip/*.h",
                      "Vendor/Minizip/aes/*.{c,h}",
                      "Vendor/Minizip/{ioapi,ioapi_mem,ioapi_buf,unzip,zip}.{c,h}",
                      "Vendor/Minizip/crypt.h" ]
  s.public_header_files = [ "Minizip/*.h", "Vendor/Minizip/{ioapi,ioapi_buf,ioapi_mem,unzip,zip}.h" ]

  s.module_map = 'Minizip/iphoneos.modulemap'
  #s.ios.module_map = 'Minizip/iphoneos.modulemap'
  #s.osx.module_map = 'Minizip/macosx.modulemap'
  #s.watchos.module_map = 'Minizip/watchos.modulemap'
  #s.tvos.module_map = 'Minizip/tvos.modulemap'

  s.library = 'z'
end
