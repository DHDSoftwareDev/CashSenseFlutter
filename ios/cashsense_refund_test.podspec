Pod::Spec.new do |s|
  s.name = 'cashsense_refund_test'
  s.version = '0.1.0'
  s.summary = 'Sandbox-only StoreKit refund testing for CashSense.'
  s.description = s.summary
  s.homepage = 'https://jojozdesigns.com'
  s.license = { :type => 'Proprietary', :text => 'Copyright DHD Software Development LLC.' }
  s.author = { 'DHD Software Development LLC' => '' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.frameworks = 'StoreKit', 'UIKit'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
