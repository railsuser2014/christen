require "eventmachine"
require "thin"
require "skinny"
require "resolv"

module Christen
  class DNSServer < EventMachine::Connection
    def receive_data data
      message = Resolv::DNS::Message.decode(data)
      puts "#{inspect}: Received: #{message.inspect}"

      if message.opcode == Resolv::DNS::OpCode::Query
        puts "#{inspect}: Query"
        domains = Set.new
        message.qr = 1
        message.each_question do |name, typeclass|
          puts "#{inspect}: Question: #{name.inspect} #{typeclass.inspect}"
          parsed = PublicSuffix.parse(name.to_s)
          if domain = Domain.find_by_name(parsed.domain)
            puts "#{inspect}: Domain: #{domain.inspect}"
            domains << domain
            if typeclass == Resolv::DNS::Resource::IN::A
              puts "#{inspect}: Looking for address record for: #{parsed.trd.inspect}"
              domain.records.where(type: AddressRecord.sti_name, name: parsed.trd).each do |record|
                puts "#{inspect}: Record: #{record.inspect}"
                message.add_answer name, record.ttl, typeclass.new(record.content)
              end
            end
            message.rcode = Resolv::DNS::RCode::NoError
          else
            puts "#{inspect}: Domain #{name.to_s.inspect} does not exist."
            message.rcode = Resolv::DNS::RCode::NXDomain
          end
        end

        domains.each do |domain|
          message.add_authority domain.name, domain.ttl,
            Resolv::DNS::Resource::IN::SOA.new(
              Resolv::DNS::Name.create("christen"),
              Resolv::DNS::Name.create("admin.christen"),
              domain.serial,
              domain.refresh,
              domain.retry_refresh,
              domain.expire,
              domain.minimum)
        end
      else
        message.rcode = Resolv::DNS::RCode::NotImp
      end

      send_data message.encode
      puts "#{inspect}: Sent: #{message.inspect}"
    end
  end

  class HTTPServer < Thin::Server
  end

  class Command
    def self.run
      new.run
    end

    def initialize
    end

    def run
      # One EventMachine loop...
      EventMachine.run do
        EventMachine.open_datagram_socket "127.0.0.1", 2053, DNSServer
        Thin::Server.start "127.0.0.1", 2080, Rails.application
      end
    end
  end
end