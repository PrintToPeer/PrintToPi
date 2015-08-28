#!/usr/bin/env ruby

if File.exists? '/boot/host.rb'
  load '/boot/host.rb'
else
  HTTP_HOST = "https://printtopeer.io"
  SOCKET_HOST = "wss://printtopeer.io"
end

puts HTTP_HOST
