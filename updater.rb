#!/usr/bin/env ruby
#Freifunk node highscore game
#Copyright (C) 2012 Anton Pirogov
#Licensed under The GPLv3

require './generator'
require './settings'

class Updater
  @@updater = nil

  def self.start
    return false if self.running?  #already running

    @@updater = Thread.new do
      Thread.current[:stop] = false
      Thread.current[:running] = true
      puts 'Started updater thread!'
      loop do
        lasttime = Time.now
        puts 'Perform score update...' if DEBUG
        result = nil
        while result.nil?
          result = Generator.execute
          if result.nil?
            puts 'Failed loading node data! Retrying in 60 seconds...'
            sleep 60
          end
        end
        puts 'Scores updated!' if DEBUG

        while (Time.now-lasttime) < INTERVAL*60
          sleep 1
          if Thread.current[:stop]
            Thread.current[:running]=false
            puts 'Stopped updater thread!'
            Thread.exit
          end
        end
      end
    end
    return true #started
  end

  def self.stop
    @@updater[:stop] = true
  end

  def self.running?
    return @@updater && @@updater[:running]
  end
end