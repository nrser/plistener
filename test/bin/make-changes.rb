#!/usr/bin/env ruby

while true
  value = rand 0...10
  puts "setting some-key = #{ value }"
  `defaults write com.nrser.plistener.test some-key #{ value }`
  sleep 3
end
