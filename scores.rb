#!/usr/bin/env ruby
#Freifunk node highscore game
#Copyright (C) 2012 Anton Pirogov
#Licensed under The GPLv3

require 'json'
require 'open-uri'

require './settings'

#write line to log if log enabled
def log(txt)
  `echo "#{Time.now.to_s}: #{txt}" >> log.txt` if LOG
end

class Scores

  @@scorepath = 'public/scores.json'

  #load apple MAC adresses once
  if PUNISHAPPLE
    #NOTE: update the applemacs.txt file with:
    #./queryvendormac.sh apple > applemacs.txt
    @@apples = File.readlines('applemacs.txt').map{|l| l.chomp.strip.downcase}
  end

  #--------

  #return last update time -> last modification to file
  def self.last_update
    return File.mtime @@scorepath
  rescue
    return Time.new(0)
  end

  #take score file and generate a sorted highscore list of requested span for output
  def self.generate(days=1, offset=0)
    scores = read_scores

    #sum up requested day scores
    scores.each{|e| e['points'] = e['points'][offset,days].to_a.inject(&:+).to_i}

    #return without nameless routers, blacklisted and losers
    scores.delete_if{|e| BLACKLIST.index e['name']}
    scores.delete_if{|e| e['name'].empty?}
    scores.delete_if{|e| e['points']<=0}

    #sort by score
    scores.sort_by! {|e| e['points']}.reverse!

    return scores
  end

  def self.reset
    File.delete @@scorepath
    return true
  rescue
    return false
  end

  #run one update cycle and generate/update the score file
  def self.update
    scores = read_scores

    #load node data
    jsonstr = nil
    begin
      jsonstr = open(JSONSRC,'r:UTF-8').read
    rescue
      return false #failed!
    end

    current_firmware_versions = fetch_firmware_versions()

    #NOTE: filtering and analyzing of JSON data fits perfectly here
    data = JSON.parse jsonstr
    snapshot = transform data
    score_firmware_for_snapshot snapshot, current_firmware_versions if current_firmware_versions
    merge scores, snapshot

    scorejson = JSON.generate scores
    File.open(@@scorepath, "w") do |f|
        f.write scorejson
    end
    return true
  end

  def self.score_firmware(current_firmware_versions, firmware)
    if not current_firmware_versions
      return ["", 0]
    end

    if not firmware
      return ["unknown", 0]
    end

    firmware = parse_firmware(firmware)

    if not firmware
      return ["custom", 0]
    end

    prev = nil
    current_firmware_versions.each do |fwinfo|
      cmp = compare_firmware_versions(firmware, fwinfo[1])
      if cmp > 0
        if prev
          return ["old " + prev[0], (prev[2]+fwinfo[2])/2]
        else
          # hm, a _very_ new one
          return ["newer than " + fwinfo[0], fwinfo[2]]
        end
      elsif cmp == 0
        return [fwinfo[0], fwinfo[2]]
      end

      prev = fwinfo
    end
 
    if prev
      return ["old", SC_OLDFIRMWARE]
    else
      return ["???", 0]
    end
  end

  def self.fetch_firmware_versions
    return nil unless BRANCHES and MANIFESTSRC and VERSION_PATTERN

    current_firmware_versions = []
    BRANCHES.each do |branch|
      version = newest_firmware_version_for_branch(branch)
      current_firmware_versions << [ branch, version, (SC_BRANCH[branch] || 0) ] if version
    end
    current_firmware_versions.sort_by! { |x| [ x[1], -BRANCHES.index(x[0]) ] }
    current_firmware_versions.reverse!
    return current_firmware_versions
  end

  def self.newest_firmware_version_for_branch(branch)
    #DEBUG
    #return [0, 3, 999, 20140527] if branch == "testing"

    begin
      manifeststr = open(MANIFESTSRC.sub("%BRANCH%", branch),'r:UTF-8').read
    rescue
      return nil
    end
    
    return self.extract_newest_firmware_version(manifeststr)
  end

  def self.extract_newest_firmware_version(manifeststr)
    max_version = nil
    manifeststr.each_line do |line|
      if line =~ /^\S+\s(#{VERSION_PATTERN})\s/
        version = parse_firmware($1)
        max_version = version if not max_version or compare_firmware_versions(version, max_version) > 0
      end
    end
    return max_version
  end

  def self.compare_firmware_versions(a, b)
    a = parse_firmware(a) unless a.is_a? Array
    b = parse_firmware(b) unless b.is_a? Array

    return a <=> b
  end

  def self.parse_firmware(fwstr)
    m = /^#{VERSION_PATTERN}$/.match(fwstr)
    return m && m.captures.collect { |x| x.to_i || x }
  end

  private

  #load current score file or fall back to empty array
  def self.read_scores
    return JSON.parse open(@@scorepath,'r:UTF-8').read
  rescue
    return []
  end

  #insert fresh new day score entry
  def self.rotate(scores)
    scores.each do |e|
      e['points'].unshift 0
      e['points'].pop if e['points'].length > 30
    end
  end
  #
  #decide by MAC address
  def self.is_apple?(node)
    return @@apples.index{|a| a==node['id'][0..7]}
  end

  #clean and prepare node data
  def self.transform(nodejson)
    nodes = nodejson['nodes']
    links = nodejson['links']

    nodes.each do |n|
      n['meshs']=[]
      n['vpns']=[]
      n['clients']=0
      n['apples']=0
    end

    links.each do |l|
      t = l['type']
      src = l['source']
      dst = l['target']

      if t.nil? #meshing
        quality=l['quality'].split(", ").map(&:to_f)
        nodes[src]['meshs'] << quality[0]
        nodes[dst]['meshs'] << quality[1] if quality.size>1
      elsif t=='vpn'
        quality=l['quality'].split(", ").map(&:to_f)
        nodes[src]['vpns'] << quality[0]
        nodes[dst]['vpns'] << quality[1] if quality.size>1
      elsif t=='client'
        nodes[src]['clients'] += 1
        nodes[dst]['clients'] += 1

        if PUNISHAPPLE
          if is_apple?(nodes[src]) || is_apple?(nodes[dst])
            nodes[src]['apples'] += 1
            nodes[dst]['apples'] += 1
          end
        end
      end
    end

    #remove clients
    routers = nodes.select{|n| n['flags']['client'] == false}

    #remove unneccesary stuff from router score json
    routers.each do |r|
      r['flags'].delete 'client' #no clients in array anyway
      r['flags'].delete 'vpn' #not used
      r['geo'] = !!r['geo']
      r.delete 'macs' #not interesting
      r.delete 'id' #not interesting
    end

    return routers
  end

  def self.score_firmware_for_snapshot(snapshot, current_firmware_versions)
    snapshot.each do |node|
      node['firmware_info'] = score_firmware(current_firmware_versions, node['firmware'])
    end
  end

  #calculate and add points for node in current round and set info for html
  def self.calc_points(node)
    #reset current status data
    node['sc_offline'] = node['sc_gateway'] = node['sc_clients'] = 0
    node['sc_apples'] = node['sc_vpns'] = node['sc_meshs'] = 0
    node['points'] = [0] if node['points'].nil?
    p = node['points']

    if !node['flags']['online']  #offline penalty
      p[0] += (node['sc_offline'] = SC_OFFLINE)
      return
    end

    p[0] += ( node['sc_gateway'] = SC_GATEWAY ) if node['flags']['gateway']

    p[0] += ( node['sc_clients'] = SC_PERCLIENT * node['clients'] )
    p[0] += ( node['sc_apples'] = SC_PERAPPLE * node['apples'] ) if PUNISHAPPLE

    p[0] += ( node['sc_vpns'] = node['vpns'].map{|e| SC_PERVPN / e}.inject(&:+).to_i )
    p[0] += ( node['sc_meshs'] = node['meshs'].map{|e| SC_PERMESH / e}.inject(&:+).to_i )

    p[0] += ( node['sc_firmware'] = ( (node['firmware_info'] && node['firmware_info'][1]) || 0 ).to_i )

    p[0] += ( node['sc_geo'] = ( node['geo'] ? (SC_GEO||0) : 0 ) )
  end

  #update scores, add new nodes, remove old nodes with <=0 points
  def self.merge(scores, data)
    #start new day points field on day change between updates
    rotate scores if last_update.day < Time.now.day

    #garbage collection:
    #detect nodes which are gone from source data (by name so node renames affected too)
    #and let them slowly die (by offline penalty)
    scores.select{|s| !data.index{|d| d['name']==s['name']}}.each do |s|
      s['flags']['online']=false
      s['flags']['gateway']=false
      s['vpns'] = []
      s['meshs'] = []
      s['clients'] = 0
      s['apples'] = 0
      s['firmware_info'] = ["?", 0]
      calc_points s
    end

    #perform regular update
    data.each do |n|
      i = scores.index{|s| s['name'] == n['name'] }
      if i.nil? #new entry
        scores.push n
        calc_points scores[-1]
      elsif #update preserving points array
        p = scores[i]['points']
        scores[i] = n
        scores[i]['points'] = p
        calc_points scores[i]
      end
    end

    return scores
  end
end
