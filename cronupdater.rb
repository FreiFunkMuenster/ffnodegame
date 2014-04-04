#!/usr/bin/env ruby
#Script to be used with cron to update the scores.json in the background
require './scores'

log 'Start score update...'

result = false
failed = 0
while !result
  begin
    result = Scores.update
  rescue
    result = false
  end
  if !result
    failed += 1
    break if failed >= 3
    log 'Failed loading node data! Retrying in 60 seconds...'
    sleep 60
  end
end

if !result
  log 'Could not update :('
  return
end

log 'Scores updated!'

