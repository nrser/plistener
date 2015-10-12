#!/usr/bin/env ruby

while true
  value = rand 0...10
  `defaults write com.nrser.plistener-test some-key #{ value }`
  sleep 3
end
