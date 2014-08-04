require 'rubygems'
require 'sequel'
require 'csv'
require 'mechanize'

YAHOO_FREE_AGENT_URL = "http://baseball.fantasysports.yahoo.com/b1/82596/players"
YAHOO_LOGIN_URL = "http://login.yahoo.com/config/login"
FANGRAPHS_PROJECTIONS_URL = "http://www.fangraphs.com/projections.aspx?type=steamerr&team=0&players=0"
BASEBALL_REFERENCE_ROOKIES_URL = "http://www.baseball-reference.com/leagues/MLB/2014-rookies.shtml"
BATTING_CATEGORIES = %w[r hr rbi sb avg obp]
PITCHING_CATEGORIES = %w[so sv era qs h_per_nine bb_per_nine]
INVERSE_CATEGORIES = %w[era h_per_nine bb_per_nine]
BATTER_POSITIONS = %w[c 1b 2b 3b ss of dh]

(puts "yahoo username and password required"; exit(1)) unless ARGV[0] && ARGV[1]

@agent = Mechanize.new
@agent.get(YAHOO_FREE_AGENT_URL) # set referrer
login = @agent.get(YAHOO_LOGIN_URL).forms.first
login.username = ARGV[0]
login.passwd = ARGV[1]
login.submit

DB = Sequel.sqlite('baseball.sqlite')

puts "creating players table"
DB.drop_table :players if DB.table_exists? :players
DB.create_table :players do
  primary_key :id
  String :name
  String :team
  String :position
  String :type
  Decimal :r
  Decimal :hr
  Decimal :rbi
  Decimal :sb
  Decimal :avg
  Decimal :obp
  Decimal :w
  Decimal :so
  Decimal :sv
  Decimal :era
  Decimal :qs
  Decimal :h_per_nine
  Decimal :bb_per_nine
  Decimal :value
  Decimal :yahoo_value, :default => 0
  TrueClass :drafted, :default => false
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
    player = {'value' => 0, 'position' => position.upcase}
    categories = if position == 'p'
                   player['h_per_nine'] = (row['h'].to_f * 9) / row['ip'].to_f
                   player['bb_per_nine'] = (row['bb'].to_f * 9) / row['ip'].to_f
                   player['qs'] = quality_starts(row)
                   PITCHING_CATEGORIES
                 else
                   BATTING_CATEGORIES
                 end
    categories.each{|c| player[c] = row[c].to_f if row[c]}
    INVERSE_CATEGORIES.each {|i| player[i] *= -1 if player[i]}
    players[row['name']] = player
  end
  players
end

def get_projections position
  url = FANGRAPHS_PROJECTIONS_URL + (position == 'p' ? "&stats=pit&pos=all" : "&stats=bat&pos=#{position}")
  projections = @agent.get(url)
  form = projections.forms.first
  form['__EVENTTARGET'] = 'ProjectionBoard1$cmdCSV'
  form['__EVENTARGUMENT'] = ''
  parse_csv form.submit.body[3..-1], position
end

def calculate players, stat
  vals = players.values.collect{|pl| pl[stat]}
  if vals.select{|v| v == 0.0} == vals
    puts("WARNING: No values found in csv for #{stat}")
    return
  end
  stddev = std_dev vals
  mean = avg vals
  players.each do |k,v| 
    v["#{stat}_val"] = ((v[stat] - mean) / stddev)
    v['value'] += v["#{stat}_val"]
  end
end

def get_free_agents type
  url = YAHOO_FREE_AGENT_URL + (type == :pitcher ? "?pos=P" : "")
  players_page = @agent.get(url)
  players = players_page.links.select{|l| l.attributes['class'] =~ /name/}.map(&:to_s)
  10.times do |i|
    print " #{type.to_s} page #{i + 1}...\r"
    players_page = players_page.link_with(:text => "Next 25").click
    players += players_page.links.select{|l| l.attributes['class'] =~ /name/}.map(&:to_s)
  end
  players
end

puts "getting projections"
batters = {}
BATTER_POSITIONS.each do |pos|
  print " #{pos}...\r"
  get_projections(pos).each do |name, player|
    existing = batters[name]
    player['position'] = "#{existing['position']},#{pos.upcase}" if existing && !existing['position'].match(pos.upcase)
    batters[name] = player
  end
end
print " p...\r"
pitchers = get_projections 'p'

puts "calculating value"
BATTING_CATEGORIES.each { |stat| calculate batters, stat }
PITCHING_CATEGORIES.each { |stat| calculate pitchers, stat }

puts "inserting players"
batters.merge(pitchers).each do |name, player|
  @players_table.insert(
    :name => name,
    :type => player['type'],
    :position => player['position'],
    :value => player['value'],
    :r => player['r'],
    :hr => player['hr'],
    :rbi => player['rbi'],
    :sb => player['sb'],
    :avg => player['avg'],
    :obp => player['obp'],
    :so => player['so'],
    :sv => player['sv'],
    :era => player['era'],
    :h_per_nine => player['h_per_nine'],
    :bb_per_nine => player['bb_per_nine'],
    :qs => player['qs'],
    :drafted => true)
end

puts "getting free agents"
free_agents = get_free_agents(:batter) + get_free_agents(:pitcher)
free_agents.each { |p| @players_table.filter(:name => p).update(:drafted => false) }

puts "updating rookies"
rookies = @agent.get(BASEBALL_REFERENCE_ROOKIES_URL)
rookies.at('table#misc_batting').css('tbody tr').each do |rookie|
  @players_table.filter(:name => rookie.css('td')[1].text).update(:rookie => true)
end
rookies.at('table#misc_pitching').css('tbody tr').each do |rookie|
  @players_table.filter(:name => rookie.css('td')[1].text).update(:rookie => true)
end

puts "updating list of 12"
@players_table.filter(:name => 'Chris, Sale').update(:list_of_twelve => true)
@players_table.filter(:name => 'Mike Minor').update(:list_of_twelve => true)
@players_table.filter(:name => 'Kris Medlen').update(:list_of_twelve => true)
@players_table.filter(:name => 'Ivan Nova').update(:list_of_twelve => true)
@players_table.filter(:name => 'Charlie Morton').update(:list_of_twelve => true)
@players_table.filter(:name => 'Chris Tillman').update(:list_of_twelve => true)
@players_table.filter(:name => 'Dillon Gee').update(:list_of_twelve => true)
@players_table.filter(:name => 'Travis Wood').update(:list_of_twelve => true)
@players_table.filter(:name => 'Jhoulys Chacin').update(:list_of_twelve => true)
@players_table.filter(:name => 'Jaime Garcia').update(:list_of_twelve => true)
@players_table.filter(:name => 'Jeremy Hellickson').update(:list_of_twelve => true)
@players_table.filter(:name => 'Tim Stauffer').update(:list_of_twelve => true)
@players_table.filter(:name => 'Ross Ohlendorf').update(:list_of_twelve => true)
@players_table.filter(:name => 'James McDonald').update(:list_of_twelve => true)
@players_table.filter(:name => 'Wade Davis').update(:list_of_twelve => true)

puts "updating prospects"
@players_table.filter(:name => "Byron Buxton").update(:prospect => true)
@players_table.filter(:name => "Xander Bogaerts").update(:prospect => true)
@players_table.filter(:name => "Oscar Taveras").update(:prospect => true)
@players_table.filter(:name => "Miguel Sano").update(:prospect => true)
@players_table.filter(:name => "Archie Bradley").update(:prospect => true)
@players_table.filter(:name => "Taijuan Walker").update(:prospect => true)
@players_table.filter(:name => "Javier Baez").update(:prospect => true)
@players_table.filter(:name => "Carlos Correa").update(:prospect => true)
@players_table.filter(:name => "Kris Bryant").update(:prospect => true)
@players_table.filter(:name => "Francisco Lindor").update(:prospect => true)
@players_table.filter(:name => "Noah Syndergaard").update(:prospect => true)
@players_table.filter(:name => "Addison Russell").update(:prospect => true)
@players_table.filter(:name => "Gregory Polanco").update(:prospect => true)
@players_table.filter(:name => "Jonathan Gray").update(:prospect => true)
@players_table.filter(:name => "Nick Castellanos").update(:prospect => true)
@players_table.filter(:name => "Jameson Taillon").update(:prospect => true)
@players_table.filter(:name => "Mark Appel").update(:prospect => true)
@players_table.filter(:name => "Albert Almora").update(:prospect => true)
@players_table.filter(:name => "Robert Stephenson").update(:prospect => true)
@players_table.filter(:name => "Dylan Bundy").update(:prospect => true)
@players_table.filter(:name => "George Springer").update(:prospect => true)
@players_table.filter(:name => "Travis d'Arnaud").update(:prospect => true)
@players_table.filter(:name => "Aaron Sanchez").update(:prospect => true)
@players_table.filter(:name => "Austin Hedges").update(:prospect => true)
@players_table.filter(:name => "Kyle Zimmer").update(:prospect => true)
@players_table.filter(:name => "Maikel Franco").update(:prospect => true)
@players_table.filter(:name => "Tyler Glasnow").update(:prospect => true)
@players_table.filter(:name => "Alex Meyer").update(:prospect => true)
@players_table.filter(:name => "Andrew Heaney").update(:prospect => true)
@players_table.filter(:name => "Henry Owens").update(:prospect => true)
@players_table.filter(:name => "Kevin Gausman").update(:prospect => true)
@players_table.filter(:name => "Kyle Crick").update(:prospect => true)
@players_table.filter(:name => "Jackie Bradley").update(:prospect => true)
@players_table.filter(:name => "Corey Seager").update(:prospect => true)
@players_table.filter(:name => "Yordano Ventura").update(:prospect => true)
@players_table.filter(:name => "Joc Pederson").update(:prospect => true)
@players_table.filter(:name => "Billy Hamilton").update(:prospect => true)
@players_table.filter(:name => "Raul Adalberto Mondesi").update(:prospect => true)
@players_table.filter(:name => "Jorge Alfaro").update(:prospect => true)
@players_table.filter(:name => "Kohl Stewart").update(:prospect => true)
@players_table.filter(:name => "Eddie Butler").update(:prospect => true)
@players_table.filter(:name => "C.J. Edwards").update(:prospect => true)
@players_table.filter(:name => "Max Fried").update(:prospect => true)
@players_table.filter(:name => "Lucas Giolito").update(:prospect => true)
@players_table.filter(:name => "Austin Meadows").update(:prospect => true)
@players_table.filter(:name => "Allen Webster").update(:prospect => true)
@players_table.filter(:name => "Gary Sanchez").update(:prospect => true)
@players_table.filter(:name => "Clint Frazier").update(:prospect => true)
@players_table.filter(:name => "Jorge Soler").update(:prospect => true)
@players_table.filter(:name => "Jonathan Singleton").update(:prospect => true)
@players_table.filter(:name => "Colin Moran").update(:prospect => true)
@players_table.filter(:name => "Lance McCullers Jr.").update(:prospect => true)
@players_table.filter(:name => "Jesse Biddle").update(:prospect => true)
@players_table.filter(:name => "Mike Foltyniewicz").update(:prospect => true)
@players_table.filter(:name => "Marcus Stroman").update(:prospect => true)
@players_table.filter(:name => "Jake Odorizzi").update(:prospect => true)
@players_table.filter(:name => "Garin Cecchini").update(:prospect => true)
@players_table.filter(:name => "Kolten Wong").update(:prospect => true)
@players_table.filter(:name => "Rougned Odor").update(:prospect => true)
@players_table.filter(:name => "Lucas Sims").update(:prospect => true)
@players_table.filter(:name => "Blake Swihart").update(:prospect => true)
@players_table.filter(:name => "Mookie Betts").update(:prospect => true)
@players_table.filter(:name => "Zach Lee").update(:prospect => true)
@players_table.filter(:name => "Julio Urias").update(:prospect => true)
@players_table.filter(:name => "Jake Marisnick").update(:prospect => true)
@players_table.filter(:name => "Delino DeShields Jr.").update(:prospect => true)
@players_table.filter(:name => "Alen Hanson").update(:prospect => true)
@players_table.filter(:name => "Eduardo Rodriguez").update(:prospect => true)
@players_table.filter(:name => "A.J. Cole").update(:prospect => true)
@players_table.filter(:name => "Erik Johnson").update(:prospect => true)
@players_table.filter(:name => "David Dahl").update(:prospect => true)
@players_table.filter(:name => "Michael Choice").update(:prospect => true)
@players_table.filter(:name => "Trevor Bauer").update(:prospect => true)
@players_table.filter(:name => "Josh Bell").update(:prospect => true)
@players_table.filter(:name => "Mason Williams").update(:prospect => true)
@players_table.filter(:name => "Luis Sardinas").update(:prospect => true)
@players_table.filter(:name => "Chris Owings").update(:prospect => true)
@players_table.filter(:name => "Matt Wisler").update(:prospect => true)
@players_table.filter(:name => "Braden Shipley").update(:prospect => true)
@players_table.filter(:name => "Matt Davidson").update(:prospect => true)
@players_table.filter(:name => "Justin Nicolino").update(:prospect => true)
@players_table.filter(:name => "Christian Bethancourt").update(:prospect => true)
@players_table.filter(:name => "Jimmy Nelson").update(:prospect => true)
@players_table.filter(:name => "Ju Hak-Lee").update(:prospect => true)
@players_table.filter(:name => "Rafael Montero").update(:prospect => true)
@players_table.filter(:name => "Matt Barnes").update(:prospect => true)
@players_table.filter(:name => "Casey Kelly").update(:prospect => true)
@players_table.filter(:name => "D.J. Peterson").update(:prospect => true)
@players_table.filter(:name => "Arismendy Alcantara").update(:prospect => true)
@players_table.filter(:name => "J.O. Berrios").update(:prospect => true)
@players_table.filter(:name => "Jorge Bonifacio").update(:prospect => true)
@players_table.filter(:name => "Joey Gallo").update(:prospect => true)
@players_table.filter(:name => "Roberto Osuna").update(:prospect => true)
@players_table.filter(:name => "Taylor Guerrieri").update(:prospect => true)
@players_table.filter(:name => "Edwin Escobar").update(:prospect => true)
@players_table.filter(:name => "Trey Ball").update(:prospect => true)
@players_table.filter(:name => "Robbie Ray").update(:prospect => true)
@players_table.filter(:name => "Stephen Piscotty").update(:prospect => true)
@players_table.filter(:name => "Rosell Herrera").update(:prospect => true)
@players_table.filter(:name => "Pierce Johnson").update(:prospect => true)
