require 'rubygems'
require 'mechanize'
require 'sequel'

DB = Sequel.sqlite('baseball.sqlite')
SITUATIONS = { 0 => { },
               1 => { '1--' => 'good', '-2-' => 'good', '--3' => 'bad', '1-3' => 'bad', '-23' => 'bad', '123' => 'bad' },
               2 => { '---' => 'good', '--3' => 'bad', '12-' => 'bad', '1-3' => 'bad', '-23' => 'bad', '123' => 'bad' } }

DB.drop_table :eight_hitters if DB.table_exists? :eight_hitters
DB.create_table :eight_hitters do
  String :batter
  String :inning
  Integer :outs
  String :baserunners
end

@agent = Mechanize.new

def parse_boxscore(url, team)
  good = 0
  bad = 0
  neutral = 0
  box = @agent.get url
  cubs_index = box.search('table#lineups th').to_a.index { |i| i.text == team }
  eight_hitter = box.search('table#lineups tbody tr')[7].search('td')[cubs_index].text.gsub(/.*\ (.*)/, '\1')
  plays = box.search('table#play_by_play tbody tr:not(.partial_table)').select { |i| i.search('td')[7].text =~ /#{eight_hitter}/ }
  inning = nil
  plays.each do |play|
    tds = play.search('td').map { |td| td.text }
    next if tds[0] == inning
    inning = tds[0]
    outs = tds[2].to_i
    baserunners = tds[3]
    case SITUATIONS[outs][baserunners]
    when 'good' then good += 1
    when 'bad' then bad += 1
    else neutral += 1
    end
    DB[:eight_hitters].insert(batter: eight_hitter, inning: inning, outs: outs, baserunners: baserunners)
  end
  [good, bad, neutral]
end

good = 0
bad = 0
neutral = 0
teams = { 'ARI' => 'Arizona Diamondbacks',
          'ATL' => 'Atlanta Braves',
          'CHC' => 'Chicago Cubs',
          'CIN' => 'Cincinnati Reds',
          'COL' => 'Colorado Rockies',
          'LAD' => 'Los Angeles Dodgers',
          'MIA' => 'Miami Marlins',
          'MIL' => 'Milwaukee Brewers',
          'NYM' => 'New York Mets',
          'PHI' => 'Philadelphia Phillies',
          'PIT' => 'Pittsburgh Pirates',
          'SDP' => 'San Diego Padres',
          'SFG' => 'San Francisco Giants',
          'STL' => 'St. Louis Cardinals',
          'WSN' => 'Washington Nationals'}
teams.each do |(team, nick)|
  puts team
  boxes = @agent.get "http://www.baseball-reference.com/teams/#{team}/2015-schedule-scores.shtml"
  boxes.search('table#team_schedule tbody tr:not(.thead)').each do |box|
    link = box.search('td')[3]
    next unless link.text == 'boxscore'
    url = 'http://www.baseball-reference.com' + link.search('a')[0].attribute('href').value
    g, b, n = parse_boxscore(url, nick)
    puts "#{url} good: #{g} bad: #{b} neutral: #{n}"
    good += g
    bad += b
    neutral += n
  end
end

puts "good: #{good}, bad: #{bad}, neutral: #{neutral}"
