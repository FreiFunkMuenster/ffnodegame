#!/usr/bin/env ruby
# encoding: UTF-8
#Freifunk node highscore game
#Copyright (C) 2012 Anton Pirogov
#Licensed under The GPLv3

#TODO: rewrite using ffmaplib

require 'json'
require 'sinatra'

require './settings'
require './scores'

unless defined? adjust_points
  def adjust_points(points)
    points
  end
end

log "---- APPLICATION STARTING ----"

get '/update' do
  if params['pw'] == PWD
    Scores.update
    'Scores updated!'
  else
    'Wrong password!'
  end
end

get '/reset' do
  if params['pw'] == PWD
    if Scores.reset && Scores.update
      'Scores reset!'
    else
      'Reset failed!'
    end
  else
    'Wrong password!'
  end
end

#----
get '/' do
  log 'Viewed by '+request.ip

  @days = params.include?('days') ? params['days'].to_i : 1
  @days = 1 if @days <= 0
  @offset = params.include?('offset') ? params['offset'].to_i : 0
  @offset = 0 if @offset < 0

  @lastupdate = Scores.last_update.strftime('am %d.%m.%Y um %H:%M')
  @scores = Scores.generate @days, @offset

  erb :index
end

helpers do
  def scores_for(days, offset)
    if days == 1
      return 'heute' if offset == 0
      return 'gestern' if offset == 1
      return 'vorgestern' if offset == 2
    end
    return 'letzte Woche' if offset == 7 && days == 7
    return "#{days} Tage" if offset == 0
    return "(benutzerdefiniert)"
  end
end
