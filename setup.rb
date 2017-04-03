require 'rubygems'
require 'sequel'
require 'csv'
require 'mechanize'
require 'active_support/inflector'

BP_FILE = 'data/pfmdata_03-29-2017_09-15-24.csv'
ZIPS_FILE = 'data/FanGraphs Leaderboard - Zips.csv'
ZIPS_PITCHERS_FILE = 'data/FanGraphs Leaderboard - Zips Pitchers.csv'
STEAMER_FILE = 'data/FanGraphs Leaderboard - Steamer.csv'
STEAMER_PITCHERS_FILE = 'data/FanGraphs Leaderboard - Steamer Pitchers.csv'

TEAMS = 12
BUDGET = 260
DOLLAR_POOL = TEAMS * BUDGET
PITCHERS_DRAFTED = 120
BATTERS_DRAFTED = 180
TOTAL_DRAFTED = PITCHERS_DRAFTED + BATTERS_DRAFTED
YAHOO_LEAGUE_ID = 34942
YAHOO_TEAM_ID = 2
YAHOO_FREE_AGENT_URL = "http://baseball.fantasysports.yahoo.com/b1/#{YAHOO_LEAGUE_ID}/players"
YAHOO_MY_TEAM_URL = "http://baseball.fantasysports.yahoo.com/b1/#{YAHOO_LEAGUE_ID}/#{YAHOO_TEAM_ID}"
YAHOO_LOGIN_URL = "http://login.yahoo.com/config/login"
FANGRAPHS_PROJECTIONS_URL = "http://www.fangraphs.com/projections.aspx?type=steamer&team=0&players=0"
BASEBALL_REFERENCE_ROOKIES_URL = "http://www.baseball-reference.com/leagues/MLB/2016-rookies.shtml"
BATTING_CATEGORIES = %w[r hr rbi sb avg obp]
PITCHING_CATEGORIES = %w[so sv era qs h_per_nine bb_per_nine]
INVERSE_CATEGORIES = %w[era h_per_nine bb_per_nine]
PLAY_TIME_THRESHOLD = 0.75
BATTER_POSITIONS = %w[c 1b 2b 3b ss of dh]
INFLATION = 1.2
POSITION_STATS = {'C'  => {pct_budget: 0.04, above_replacement: 12},
                  '1B' => {pct_budget: 0.12, above_replacement: 25},
                  '2B' => {pct_budget: 0.08, above_replacement: 20},
                  '3B' => {pct_budget: 0.10, above_replacement: 20},
                  'SS' => {pct_budget: 0.08, above_replacement: 20},
                  'OF' => {pct_budget: 0.25, above_replacement: 80},
                  'DH' => {pct_budget: 0.04, above_replacement: 2},
                  'SP' => {pct_budget: 0.25, above_replacement: 80},
                  'RP' => {pct_budget: 0.07, above_replacement: 30}}
BATTING_RATE_CATEGORIES = {'avg' => 'ab', 'obp' => 'ab'}
PITCHING_RATE_CATEGORIES = {'era' => 'ip', 'h_per_nine' => 'ip', 'bb_per_nine' => 'ip'}

(puts "yahoo username and password required"; exit(1)) unless ARGV[0] && ARGV[1]

DB = Sequel.sqlite('baseball.sqlite')

@agent = Mechanize.new

puts "creating players table"
DB.drop_table :players if DB.table_exists? :players
DB.create_table :players do
  primary_key :id
  String :name
  String :team
  String :position
  String :type
  Decimal :ab
  Decimal :r
  Decimal :hr
  Decimal :rbi
  Decimal :sb
  Decimal :avg
  Decimal :obp
  Decimal :ip
  Decimal :w
  Decimal :so
  Decimal :sv
  Decimal :era
  Decimal :qs
  Decimal :h_per_nine
  Decimal :bb_per_nine
  Decimal :r_val
  Decimal :hr_val
  Decimal :rbi_val
  Decimal :sb_val
  Decimal :avg_val
  Decimal :obp_val
  Decimal :w_val
  Decimal :so_val
  Decimal :sv_val
  Decimal :era_val
  Decimal :qs_val
  Decimal :h_per_nine_val
  Decimal :bb_per_nine_val
  Decimal :bp_value, :default => 0
  Decimal :zips_value, :default => 0
  Decimal :steamer_value, :default => 0
  Decimal :median_value, :default => 0
  Decimal :yahoo_rank, :default => 0
  Decimal :yahoo_current, :default => 0
  TrueClass :drafted, :default => false
  TrueClass :mine, :default => false
  TrueClass :list_of_twelve, :default => false
  TrueClass :sleeper, :default => false
  TrueClass :injury, :default => false
  TrueClass :favorite, :default => false
  TrueClass :prospect, :default => false
  TrueClass :rookie, :default => false
end

DB.add_index :players, :id
@players_table = DB[:players]

def avg values
  values.inject(:+) / values.size.to_f
end

def std_dev values
  mean = avg values
  Math.sqrt( values.inject(0){ |sum, e| sum + (e - mean) ** 2 } / values.size.to_f )
end

def quality_starts row
  #http://www.mrcheatsheet.com/2012/03/classic-expected-quality-starts-formula.html
  return 0.0 if row['gs'].to_f == 0.0
  (((row['ip'].to_f / row['gs'].to_f) / 6.15) - (0.11 * row['era'].to_f)) * row['gs'].to_f
end

def parse_csv csv, position
  players = {}
  CSV.parse(csv, {:headers => true, :header_converters => :downcase}).each do |row|
    player = { 'position' => position.upcase}
    categories = if position == 'p'
                   player['h_per_nine'] = (row['h'].to_f * 9) / row['ip'].to_f
                   player['bb_per_nine'] = (row['bb'].to_f * 9) / row['ip'].to_f
                   player['ip'] = row['ip'].to_f
                   player['qs'] = quality_starts(row)
                   player['position'] = row['gs'].to_f > 0 ? 'SP' : 'RP'
                   PITCHING_CATEGORIES
                 else
                   player['ab'] = row['ab'].to_f
                   BATTING_CATEGORIES
                 end
    categories.each{|c| player[c] = row[c].to_f if row[c]}
    INVERSE_CATEGORIES.each {|i| player[i] *= -1 if player[i]}
    players[row['name']] = player
  end
  players
end

def get_projections position
  print " #{position}...\r"
  url = FANGRAPHS_PROJECTIONS_URL + (position == 'p' ? "&stats=pit&pos=all" : "&stats=bat&pos=#{position}")
  projections = @agent.get(url)
  form = projections.forms.first
  form['__EVENTTARGET'] = 'ProjectionBoard1$cmdCSV'
  form['__EVENTARGUMENT'] = ''
  parse_csv form.submit.body[3..-1], position
end

def calculate players, stat, rates
  filtered = players.values.collect{|p| p[stat]}.select{|v| v != 0.0}
  if filtered.empty?
    if players.first.last['position'] == 'RP' && stat == 'qs'
      players.each{|k,v| v["qs_val"] = 0.0}
    elsif players.first.last['position'] == 'SP' && stat == 'sv'
      players.each{|k,v| v["sv_val"] = 0.0}
    else
      puts("WARNING: No values found in csv for #{stat}")
    end
    return
  end
  stddev = std_dev filtered
  mean = avg filtered
  players.each do |k,v|
    v["#{stat}_val"] = stddev == 0 ? 0 : (v[stat] - mean) / stddev
    rates.has_key?(stat) ? (v["#{stat}_val"] = v["#{stat}_val"] * v[rates[stat]]) : (v['value'] += v["#{stat}_val"])
  end
end

def recalculate_rate players, stat, rate_cat
  filtered = players.values.collect{|p| p["#{stat}_val"]}
  stddev = std_dev filtered
  mean = avg filtered
  players.each do |k,v|
    v["#{stat}_val"] = (v["#{stat}_val"] - mean) / stddev
    v['value'] += v["#{stat}_val"]
  end
end

def calculate_dollar_value position, players
  pool = DOLLAR_POOL * POSITION_STATS[position][:pct_budget]
  index = POSITION_STATS[position][:above_replacement]
  players = players.sort_by{|_,p| p['value']}.reverse
  replacement = players.to_a[index + 1].last['value']
  avg_fvar = players.take(index).map{|_,p| p['value'] - replacement}.inject(:+) / index
  players.each do |n,p|
    fvar = p['value'] - replacement
    dollars = (((fvar / avg_fvar) * pool) / (index - 1)) * INFLATION
    dollars = dollars < 1 ? 1 : dollars
    dollars = 0 if position == 'DH'
    dollars = [dollars, p['dollars']].max if p['dollars']
    p['dollars'] = dollars
  end
end

def get_free_agents type
  url = YAHOO_FREE_AGENT_URL + (type == :pitcher ? "?pos=P" : "?pos=B")
  players_page = @agent.get(url)
  players = players_page.links.select{|l| l.attributes['class'] =~ /name/}.map{|p| ActiveSupport::Inflector.transliterate(p.to_s)}
  10.times do |i|
    print " #{type.to_s} page #{i + 1}...\r"
    players_page = players_page.link_with(:text => "Next 25").click
    players += players_page.links.select{|l| l.attributes['class'] =~ /name/}.map{|p| ActiveSupport::Inflector.transliterate(p.to_s)}
  end
  players
end

def set_yahoo_rank player
  name = ActiveSupport::Inflector.transliterate(player.search('.name').text)
  rank = player.search('td')[6].text
  current = player.search('td')[7].text
  @players_table.filter(:name => name).update(:yahoo_rank => rank, :yahoo_current => current) if name && rank && current
end

def update_yahoo_ranks type
  url = YAHOO_FREE_AGENT_URL + (type == :pitcher ? "?pos=P" : "?pos=B") + "&status=ALL"
  players_page = @agent.get(url)
  players_page.search('table.Table.Table-px-xs tbody tr').each { |player| set_yahoo_rank(player) }
  15.times do |i|
    puts " #{type.to_s} page #{i + 1}...\r"
    puts players_page.links.inspect
    players_page = players_page.link_with(:text => "Next 25").click
    players_page.search('table.Table.Table-px-xs tbody tr').each { |player| set_yahoo_rank(player) }
  end
end

@agent.get(YAHOO_FREE_AGENT_URL) # set referrer
login = @agent.get(YAHOO_LOGIN_URL).forms.first
login.username = ARGV[0]
login.passwd = ARGV[1]
login.submit

puts "getting projections"
batters = {}
BATTER_POSITIONS.each do |pos|
  get_projections(pos).each do |name, player|
    existing = batters[name]
    player['position'] = "#{existing['position']},#{pos.upcase}" if existing && !existing['position'].match(pos.upcase)
    batters[name] = player
  end
end
pitchers = get_projections 'p'

starting_pitchers = pitchers.select{|_,p| p['position'] == 'SP'}
relief_pitchers = pitchers.select{|_,p| p['position'] == 'RP' && p['sv'] > 1}

puts "calculating value"
#batters = batters.sort_by{|_,p| p['ab']}.reverse.take((batters.size * PLAY_TIME_THRESHOLD).ceil).to_h
#starting_pitchers = starting_pitchers.sort_by{|_,p| p['ip']}.reverse.take((starting_pitchers.size * PLAY_TIME_THRESHOLD).ceil).to_h
#BATTING_CATEGORIES.each { |stat| calculate batters, stat, BATTING_RATE_CATEGORIES }
#PITCHING_CATEGORIES.each { |stat| calculate starting_pitchers, stat, PITCHING_RATE_CATEGORIES }
#PITCHING_CATEGORIES.each { |stat| calculate relief_pitchers, stat, PITCHING_RATE_CATEGORIES }
#BATTING_RATE_CATEGORIES.each { |k,v| recalculate_rate batters, k, v }
#PITCHING_RATE_CATEGORIES.each { |k,v| recalculate_rate starting_pitchers, k, v }
#PITCHING_RATE_CATEGORIES.each { |k,v| recalculate_rate relief_pitchers, k, v }

puts "calculating dollar values"
#calculate_dollar_value 'DH', batters.select{|_,p| p['position'] =~ /DH/}
#calculate_dollar_value 'C',  batters.select{|_,p| p['position'] =~ /C/}
#calculate_dollar_value '2B', batters.select{|_,p| p['position'] =~ /2B/}
#calculate_dollar_value 'SS', batters.select{|_,p| p['position'] =~ /SS/}
#calculate_dollar_value '3B', batters.select{|_,p| p['position'] =~ /3B/}
#calculate_dollar_value '1B', batters.select{|_,p| p['position'] =~ /1B/}
#calculate_dollar_value 'OF', batters.select{|_,p| p['position'] =~ /OF/}
#calculate_dollar_value 'SP', starting_pitchers
#calculate_dollar_value 'RP', relief_pitchers

puts "adding baseball prospectus values"
CSV.open(BP_FILE, headers: true, header_converters: [:downcase]).each do |player|
  name = "#{player['player'].split(',')[1]} #{player['player'].split(',')[0]}".strip
  batters[name]['bp_value'] = player['$$$'].gsub('$', '').gsub('(', '-').gsub(')', '').to_f if batters[name]
  starting_pitchers[name]['bp_value'] = player['$$$'].gsub('$', '').gsub('(', '-').gsub(')', '').to_f if starting_pitchers[name]
  relief_pitchers[name]['bp_value'] = player['$$$'].gsub('$', '').gsub('(', '-').gsub(')', '').to_f if relief_pitchers[name]
end

puts "adding zips values"
CSV.open(ZIPS_FILE, headers: true, header_converters: [:downcase]).each do |player|
  batters[player['playername']]['zips_value'] = player['dollars'].gsub('$', '').gsub('(', '-').gsub(')', '').to_f  if batters[player['playername']]
end
CSV.open(ZIPS_PITCHERS_FILE, headers: true, header_converters: [:downcase]).each do |player|
  starting_pitchers[player['playername']]['zips_value'] = player['dollars'].gsub('$', '').gsub('(', '-').gsub(')', '').to_f if starting_pitchers[player['playername']]
  relief_pitchers[player['playername']]['zips_value'] = player['dollars'].gsub('$', '').gsub('(', '-').gsub(')', '').to_f if relief_pitchers[player['playername']]
end

puts "adding steamer values"
CSV.open(STEAMER_FILE, headers: true, header_converters: [:downcase]).each do |player|
  batters[player['playername']]['steamer_value'] = player['dollars'].gsub('$', '').gsub('(', '-').gsub(')', '').to_f if batters[player['playername']]
end
CSV.open(STEAMER_PITCHERS_FILE, headers: true, header_converters: [:downcase]).each do |player|
  starting_pitchers[player['playername']]['steamer_value'] = player['dollars'].gsub('$', '').gsub('(', '-').gsub(')', '').to_f if starting_pitchers[player['playername']]
  relief_pitchers[player['playername']]['steamer_value'] = player['dollars'].gsub('$', '').gsub('(', '-').gsub(')', '').to_f if relief_pitchers[player['playername']]
end

puts "inserting players"
batters.merge(starting_pitchers).merge(relief_pitchers).each do |name, player|
  begin
  @players_table.insert(
    :name => name,
    :type => player['type'],
    :position => player['position'],
    :ab => player['ab'],
    :r => player['r'],
    :hr => player['hr'],
    :rbi => player['rbi'],
    :sb => player['sb'],
    :avg => player['avg'],
    :obp => player['obp'],
    :ip => player['ip'],
    :so => player['so'],
    :sv => player['sv'],
    :era => player['era'],
    :h_per_nine => player['h_per_nine'],
    :bb_per_nine => player['bb_per_nine'],
    :qs => player['qs'],
    :bp_value => player['bp_value'] || 0,
    :zips_value => player['zips_value'] || 0,
    :steamer_value => player['steamer_value'] || 0,
    :median_value => [player['bp_value'] || 0, player['zips_value'] || 0, player['steamer_value'] || 0].sort[1],
    :drafted => false)
  rescue ArgumentError => e
    puts player.inspect
    raise e
  end
end

puts "updating yahoo ranks"
#update_yahoo_ranks :batter
#update_yahoo_ranks :pitcher

puts "getting free agents"
#free_agents = get_free_agents(:batter) + get_free_agents(:pitcher)
#free_agents.each { |p| @players_table.filter(:name => p).update(:drafted => false) }

puts "updating rookies"
#rookies = @agent.get(BASEBALL_REFERENCE_ROOKIES_URL)
#rookies.at('table#misc_batting').css('tbody tr').each do |rookie|
  #@players_table.filter(:name => rookie.css('td')[1].text).update(:rookie => true)
#end
#rookies.at('table#misc_pitching').css('tbody tr').each do |rookie|
  #@players_table.filter(:name => rookie.css('td')[1].text).update(:rookie => true)
#end

#puts "updating my team"
##team = @agent.get(YAHOO_MY_TEAM_URL)
##team.search('.ysf-player-name > a.name').map(&:text).each do |p|
  ##@players_table.filter(:name => p).update(:mine => true)
##end

puts "updating list of 12"
#@players_table.filter(:name => 'Corey Kluber').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Dallas Keuchel').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Sonny Gray').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Carlos Carrasco').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Chris Archer').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Tyson Ross').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Shelby Miller').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Garrett Richards').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Julio Teheran').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Andrew Cashner').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Nathan Eovaldi').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Hector Santiago').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Wily Peralta').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Rich Hill').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Jeff Locke').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Tom Koehler').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Josh Tomlin').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Jesse Chavez').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Miguel Gonzalez').update(:list_of_twelve => true)

puts 'updating prospects'
@players_table.filter(:name => 'Austin Meadows').update(:prospect => true)
@players_table.filter(:name => 'Manuel Margot').update(:prospect => true)
@players_table.filter(:name => 'Trey Mancini').update(:prospect => true)
@players_table.filter(:name => 'Ozzie Albies').update(:prospect => true)
@players_table.filter(:name => 'Tyler Glasnow').update(:prospect => true)
@players_table.filter(:name => 'Clint Frazier').update(:prospect => true)
@players_table.filter(:name => 'J.P. Crawford').update(:prospect => true)
@players_table.filter(:name => 'Josh Bell').update(:prospect => true)
@players_table.filter(:name => 'Robert Gsellman').update(:prospect => true)
@players_table.filter(:name => 'Lucas Giolito').update(:prospect => true)
@players_table.filter(:name => 'Yulieski Gurriel').update(:prospect => true)
@players_table.filter(:name => 'Jose De Leon').update(:prospect => true)
@players_table.filter(:name => 'Reynaldo Lopez').update(:prospect => true)
@players_table.filter(:name => 'Francis Martes').update(:prospect => true)
@players_table.filter(:name => 'Lewis Brinson').update(:prospect => true)
@players_table.filter(:name => 'Mitch Haniger').update(:prospect => true)
@players_table.filter(:name => 'Jharel Cotton').update(:prospect => true)
@players_table.filter(:name => 'Amed Rosario').update(:prospect => true)
@players_table.filter(:name => 'Yoan Moncada').update(:prospect => true)
@players_table.filter(:name => 'Dansby Swanson').update(:prospect => true)
@players_table.filter(:name => 'Andrew Benintendi').update(:prospect => true)
