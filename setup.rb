require 'rubygems'
require 'sequel'
require 'csv'

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
  Decimal :k
  Decimal :s
  Decimal :era
  Decimal :qs
  Decimal :h_per_nine
  Decimal :bb_per_nine
  Decimal :war
  Decimal :value
  Decimal :yahoo_value, :default => 0
  TrueClass :drafted, :default => false
  TrueClass :list_of_twelve, :default => false
  TrueClass :sleeper, :default => false
  TrueClass :injury, :default => false
  TrueClass :favorite, :default => false
  TrueClass :prospect, :default => false
end

DB.add_index :players, :id
@players_table = DB[:players]

puts "calculating stats"
def std_dev values
  count = values.size
  mean = values.inject(:+) / count.to_f
  Math.sqrt( values.inject(0) { |sum, e| sum + (e - mean) ** 2 } / count.to_f )
end

def parse_csv file, type
  players = {}
  CSV.open(file, {:headers => true, :header_converters => :downcase}).each do |row|
    categories = type == :batter ?
      ['r', 'hr', 'rbi', 'sb', 'avg', 'obp'] : 
      ['k', 's', 'era', 'war']
    players[row['name']] = {'type' => type.to_s, 'value' => 0}
    categories.each{|c| players[row['name']][c] = row[c].to_f}
    if type == :pitcher
      players[row['name']]['h_per_nine'] = (row['h'].to_f * 9) / row['ip'].to_f
      players[row['name']]['bb_per_nine'] = (row['bb'].to_f * 9) / row['ip'].to_f
      ['era', 'h_per_nine', 'bb_per_nine'].each {|p| players[row['name']][p] *= -1 }
    end
  end
  players
end

def calculate players, stat
  vals = players.values.collect{|pl| pl[stat]}
  if vals.select{|v| v == 0.0} == vals
    puts("WARNING: No values found in csv file for #{stat}")
    return
  end
  stddev = std_dev vals
  mean = vals.inject(:+) / vals.size.to_f
  players.each do |k,v| 
    v["#{stat}_val"] = ((v[stat] - mean) / stddev)
    v['value'] += v["#{stat}_val"]
  end
end

batters = parse_csv 'data/batters_mid.csv', :batter
['r', 'hr', 'rbi', 'sb', 'avg', 'obp'] .each do |stat|
  calculate batters, stat
end
pitchers = parse_csv 'data/pitchers_mid.csv', :pitcher
['k', 's', 'era', 'h_per_nine', 'bb_per_nine', 'war'].each do |stat|
  calculate pitchers, stat
end

puts "inserting players"
batters.merge(pitchers).each do |name, player|
  @players_table.insert(
    :name => name,
    :type => player['type'],
    :value => player['value'],
    :r => player['r'],
    :hr => player['hr'],
    :rbi => player['rbi'],
    :sb => player['sb'],
    :avg => player['avg'],
    :obp => player['obp'],
    :k => player['k'],
    :s => player['s'],
    :era => player['era'],
    :h_per_nine => player['h_per_nine'],
    :bb_per_nine => player['bb_per_nine'],
    :war => player['war'])
end

#puts "updating list of 12"
#@players_table.filter(:name => 'Sale, Chris').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Minor, Mike').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Medlen, Kris').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Nova, Ivan').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Morton, Charlie').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Tillman, Chris').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Gee, Dillon').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Wood, Travis').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Chacin, Jhoulys').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Garcia, Jaime').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Hellickson, Jeremy').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Stauffer, Tim').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Ohlendorf, Ross').update(:list_of_twelve => true)
#@players_table.filter(:name => 'McDonald, James').update(:list_of_twelve => true)
#@players_table.filter(:name => 'Davis, Wade').update(:list_of_twelve => true)

#puts "updating keepers"
#@players_table.filter(:name => 'Perkins, Glen').update(:drafted => true)
#@players_table.filter(:name => 'Scherzer, Max').update(:drafted => true)
#@players_table.filter(:name => 'Fernandez, Jose').update(:drafted => true)
#@players_table.filter(:name => 'Segura, Jean').update(:drafted => true)
#@players_table.filter(:name => 'Desmond, Ian').update(:drafted => true)
#@players_table.filter(:name => 'Pedrioa, Dustin').update(:drafted => true)
#@players_table.filter(:name => 'Ryu, Hyun-jin').update(:drafted => true)
#@players_table.filter(:name => 'Uehara, Koju').update(:drafted => true)
#@players_table.filter(:name => 'Ramirez, Hanley').update(:drafted => true)
#@players_table.filter(:name => 'Iwakuma, Hisashi').update(:drafted => true)
#@players_table.filter(:name => 'Jansen, Kenley').update(:drafted => true)
#@players_table.filter(:name => 'Posey, Buster').update(:drafted => true)
#@players_table.filter(:name => 'Puig, Yasiel').update(:drafted => true)
#@players_table.filter(:name => 'Trout, Mike').update(:drafted => true)
#@players_table.filter(:name => 'Goldschmidt, Paul').update(:drafted => true)
#@players_table.filter(:name => 'Hamilton, Billy').update(:drafted => true)
#@players_table.filter(:name => 'Jones, Adam').update(:drafted => true)
#@players_table.filter(:name => 'Adams, Matt').update(:drafted => true)
#@players_table.filter(:name => 'Prado, Martín').update(:drafted => true)
#@players_table.filter(:name => 'Choo, Shin Shoo').update(:drafted => true)
#@players_table.filter(:name => 'Kipnis, Jason').update(:drafted => true)
#@players_table.filter(:name => 'Holland, Greg').update(:drafted => true)
#@players_table.filter(:name => 'Wacha, Michael').update(:drafted => true)
#@players_table.filter(:name => 'Seager, Kyle').update(:drafted => true)
#@players_table.filter(:name => 'Davis, Chris').update(:drafted => true)
#@players_table.filter(:name => 'Simmons, Andrelton').update(:drafted => true)
#@players_table.filter(:name => 'Machado, Manny').update(:drafted => true)
#@players_table.filter(:name => 'Brown, Dominic').update(:drafted => true)
#@players_table.filter(:name => 'Myers, Wil').update(:drafted => true)
#@players_table.filter(:name => 'Cole, Gerritt').update(:drafted => true)
#@players_table.filter(:name => 'Rizzo, Anthony').update(:drafted => true)
#@players_table.filter(:name => 'Werth, Jason').update(:drafted => true)
#@players_table.filter(:name => 'Harper, Bryce').update(:drafted => true)
#@players_table.filter(:name => 'Kershaw, Clayton').update(:drafted => true)
#@players_table.filter(:name => 'Lee, Cliff').update(:drafted => true)
#@players_table.filter(:name => 'Gordon, Alex').update(:drafted => true)
#@players_table.filter(:name => 'Gomez, Carlos').update(:drafted => true)
#@players_table.filter(:name => 'Craig, Allen').update(:drafted => true)
#@players_table.filter(:name => 'Gray, Sonny').update(:drafted => true)
#@players_table.filter(:name => 'Alvarez, Pedro').update(:drafted => true)
#@players_table.filter(:name => 'Encarnacion, Edwin').update(:drafted => true)
#@players_table.filter(:name => 'Donaldson, Josh').update(:drafted => true)
#@players_table.filter(:name => 'Darvish, Yu').update(:drafted => true)
#@players_table.filter(:name => 'Cabrera, Evereth').update(:drafted => true)
#@players_table.filter(:name => 'Sale, Chris').update(:drafted => true)
#@players_table.filter(:name => 'Carpenter, Matt').update(:drafted => true)
#@players_table.filter(:name => 'Cobb, Alex').update(:drafted => true)
#@players_table.filter(:name => 'Holliday, Matt').update(:drafted => true)

#puts "updating injured players"
#@players_table.filter(:name => "Burnett, Sean").update(:injury => true)
#@players_table.filter(:name => "De La Rosa, Dane").update(:injury => true)
#@players_table.filter(:name => "Moran, Brian").update(:injury => true)
#@players_table.filter(:name => "Crain, Jesse").update(:injury => true)
#@players_table.filter(:name => "White, Alex").update(:injury => true)
#@players_table.filter(:name => "Cook, Ryan").update(:injury => true)
#@players_table.filter(:name => "Gentry, Craig").update(:injury => true)
#@players_table.filter(:name => "Griffin, A.J.").update(:injury => true)
#@players_table.filter(:name => "O'Flaherty, Eric").update(:injury => true)
#@players_table.filter(:name => "Parker, Jarrod").update(:injury => true)
#@players_table.filter(:name => "Happ, J.A.").update(:injury => true)
#@players_table.filter(:name => "Reyes, Jose").update(:injury => true)
#@players_table.filter(:name => "Beachy, Brandon").update(:injury => true)
#@players_table.filter(:name => "Floyd, Gavin").update(:injury => true)
#@players_table.filter(:name => "Medlen, Kris").update(:injury => true)
#@players_table.filter(:name => "Minor, Mike").update(:injury => true)
#@players_table.filter(:name => "Venters, Jonny").update(:injury => true)
#@players_table.filter(:name => "Gorzelanny, Tom").update(:injury => true)
#@players_table.filter(:name => "Segura, Jean").update(:injury => true)
#@players_table.filter(:name => "Garcia, Jaime").update(:injury => true)
#@players_table.filter(:name => "Motte, Jason").update(:injury => true)
#@players_table.filter(:name => "Arrieta, Jake").update(:injury => true)
#@players_table.filter(:name => "Fujikawa, Kyuji").update(:injury => true)
#@players_table.filter(:name => "McDonald, James").update(:injury => true)
#@players_table.filter(:name => "Arroyo, Bronson").update(:injury => true)
#@players_table.filter(:name => "Corbin, Patrick").update(:injury => true)
#@players_table.filter(:name => "Hernandez, David").update(:injury => true)
#@players_table.filter(:name => "Reynolds, Matt").update(:injury => true)
#@players_table.filter(:name => "Ross, Cody").update(:injury => true)
#@players_table.filter(:name => "Beckett, Josh").update(:injury => true)
#@players_table.filter(:name => "Billingsley, Chad").update(:injury => true)
#@players_table.filter(:name => "Elbert, Scott").update(:injury => true)
#@players_table.filter(:name => "Garcia, Onelki").update(:injury => true)
#@players_table.filter(:name => "Greinke, Zack").update(:injury => true)
#@players_table.filter(:name => "Kemp, Matt").update(:injury => true)
#@players_table.filter(:name => "Kershaw, Clayton").update(:injury => true)
#@players_table.filter(:name => "Puig, Yasiel").update(:injury => true)
#@players_table.filter(:name => "Scutaro, Marco").update(:injury => true)
#@players_table.filter(:name => "Bourn, Michael").update(:injury => true)
#@players_table.filter(:name => "Iwakuma, Hisashi").update(:injury => true)
#@players_table.filter(:name => "Pryor, Stephen").update(:injury => true)
#@players_table.filter(:name => "Walker, Taijuan").update(:injury => true)
#@players_table.filter(:name => "Furcal, Rafael").update(:injury => true)
#@players_table.filter(:name => "Lucas, Ed").update(:injury => true)
#@players_table.filter(:name => "Harvey, Matt").update(:injury => true)
#@players_table.filter(:name => "Niese, Jonathon").update(:injury => true)
#@players_table.filter(:name => "Davis, Erik").update(:injury => true)
#@players_table.filter(:name => "Fister, Doug").update(:injury => true)
#@players_table.filter(:name => "Mattheus, Ryan").update(:injury => true)
#@players_table.filter(:name => "Ohlendorf, Ross").update(:injury => true)
#@players_table.filter(:name => "Machado, Manny").update(:injury => true)
#@players_table.filter(:name => "Peguero, Francisco").update(:injury => true)
#@players_table.filter(:name => "Reimold, Nolan").update(:injury => true)
#@players_table.filter(:name => "Johnson, Josh").update(:injury => true)
#@players_table.filter(:name => "Kelly, Casey").update(:injury => true)
#@players_table.filter(:name => "Luebke, Cory").update(:injury => true)
#@players_table.filter(:name => "Maybin, Cameron").update(:injury => true)
#@players_table.filter(:name => "Wieland, Joseph").update(:injury => true)
#@players_table.filter(:name => "Adams, Mike").update(:injury => true)
#@players_table.filter(:name => "Galvis, Freddy").update(:injury => true)
#@players_table.filter(:name => "Gonzalez, Miguel").update(:injury => true)
#@players_table.filter(:name => "Hamels, Cole").update(:injury => true)
#@players_table.filter(:name => "Martin, Ethan").update(:injury => true)
#@players_table.filter(:name => "Pettibone, Jonathan").update(:injury => true)
#@players_table.filter(:name => "Ruf, Darin").update(:injury => true)
#@players_table.filter(:name => "Stewart, Chris").update(:injury => true)
#@players_table.filter(:name => "Beltre, Engel").update(:injury => true)
#@players_table.filter(:name => "Darvish, Yu").update(:injury => true)
#@players_table.filter(:name => "Harrison, Matt").update(:injury => true)
#@players_table.filter(:name => "Holland, Derek").update(:injury => true)
#@players_table.filter(:name => "Ortiz, Joseph").update(:injury => true)
#@players_table.filter(:name => "Profar, Jurickson").update(:injury => true)
#@players_table.filter(:name => "Soto, Geovany").update(:injury => true)
#@players_table.filter(:name => "Hellickson, Jeremy").update(:injury => true)
#@players_table.filter(:name => "Breslow, Craig").update(:injury => true)
#@players_table.filter(:name => "Wright, Steven").update(:injury => true)
#@players_table.filter(:name => "Broxton, Jonathan").update(:injury => true)
#@players_table.filter(:name => "Chapman, Aroldis").update(:injury => true)
#@players_table.filter(:name => "Hannahan, Jack").update(:injury => true)
#@players_table.filter(:name => "Latos, Mat").update(:injury => true)
#@players_table.filter(:name => "Marshall, Sean").update(:injury => true)
#@players_table.filter(:name => "Mesoraco, Devin").update(:injury => true)
#@players_table.filter(:name => "Schumaker, Skip").update(:injury => true)
#@players_table.filter(:name => "Chacin, Jhoulys").update(:injury => true)
#@players_table.filter(:name => "Logan, Boone").update(:injury => true)
#@players_table.filter(:name => "Hochevar, Luke").update(:injury => true)
#@players_table.filter(:name => "Infante, Omar").update(:injury => true)
#@players_table.filter(:name => "Dirks, Andy").update(:injury => true)
#@players_table.filter(:name => "Iglesias, Jose").update(:injury => true)
#@players_table.filter(:name => "Rondon, Bruce").update(:injury => true)
#@players_table.filter(:name => "Florimon, Pedro").update(:injury => true)
#@players_table.filter(:name => "Beckham, Gordon").update(:injury => true)
#@players_table.filter(:name => "Keppinger, Jeff").update(:injury => true)
#@players_table.filter(:name => "Ryan, Brendan").update(:injury => true)

#puts "updating prospects"
#@players_table.filter(:name => "Buxton, Byron").update(:prospect => true)
#@players_table.filter(:name => "Bogaerts, Xander").update(:prospect => true)
#@players_table.filter(:name => "Taveras, Oscar").update(:prospect => true)
#@players_table.filter(:name => "Sano, Miguel").update(:prospect => true)
#@players_table.filter(:name => "Bradley, Archie").update(:prospect => true)
#@players_table.filter(:name => "Walker, Taijuan").update(:prospect => true)
#@players_table.filter(:name => "Baez, Javier").update(:prospect => true)
#@players_table.filter(:name => "Correa, Carlos").update(:prospect => true)
#@players_table.filter(:name => "Bryant, Kris").update(:prospect => true)
#@players_table.filter(:name => "Lindor, Francisco").update(:prospect => true)
#@players_table.filter(:name => "Syndergaard, Noah").update(:prospect => true)
#@players_table.filter(:name => "Russell, Addison").update(:prospect => true)
#@players_table.filter(:name => "Polanco, Gregory").update(:prospect => true)
#@players_table.filter(:name => "Gray, Jonathan").update(:prospect => true)
#@players_table.filter(:name => "Castellanos, Nick").update(:prospect => true)
#@players_table.filter(:name => "Taillon, Jameson").update(:prospect => true)
#@players_table.filter(:name => "Appel, Mark").update(:prospect => true)
#@players_table.filter(:name => "Almora, Albert").update(:prospect => true)
#@players_table.filter(:name => "Stephenson, Robert").update(:prospect => true)
#@players_table.filter(:name => "Bundy, Dylan").update(:prospect => true)
#@players_table.filter(:name => "Springer, George").update(:prospect => true)
#@players_table.filter(:name => "d'Arnaud, Travis").update(:prospect => true)
#@players_table.filter(:name => "Sanchez, Aaron").update(:prospect => true)
#@players_table.filter(:name => "Hedges, Austin").update(:prospect => true)
#@players_table.filter(:name => "Zimmer, Kyle").update(:prospect => true)
#@players_table.filter(:name => "Franco, Maikel").update(:prospect => true)
#@players_table.filter(:name => "Glasnow, Tyler").update(:prospect => true)
#@players_table.filter(:name => "Meyer, Alex").update(:prospect => true)
#@players_table.filter(:name => "Heaney, Andrew").update(:prospect => true)
#@players_table.filter(:name => "Owens, Henry").update(:prospect => true)
#@players_table.filter(:name => "Gausman, Kevin").update(:prospect => true)
#@players_table.filter(:name => "Crick, Kyle").update(:prospect => true)
#@players_table.filter(:name => "Bradley, Jackie").update(:prospect => true)
#@players_table.filter(:name => "Seager, Corey").update(:prospect => true)
#@players_table.filter(:name => "Ventura, Yordano").update(:prospect => true)
#@players_table.filter(:name => "Pederson, Joc").update(:prospect => true)
#@players_table.filter(:name => "Hamilton, Billy").update(:prospect => true)
#@players_table.filter(:name => "Adalberto Mondesi, Raul").update(:prospect => true)
#@players_table.filter(:name => "Alfaro, Jorge").update(:prospect => true)
#@players_table.filter(:name => "Stewart, Kohl").update(:prospect => true)
#@players_table.filter(:name => "Butler, Eddie").update(:prospect => true)
#@players_table.filter(:name => "Edwards, C.J.").update(:prospect => true)
#@players_table.filter(:name => "Fried, Max").update(:prospect => true)
#@players_table.filter(:name => "Giolito, Lucas").update(:prospect => true)
#@players_table.filter(:name => "Meadows, Austin").update(:prospect => true)
#@players_table.filter(:name => "Webster, Allen").update(:prospect => true)
#@players_table.filter(:name => "Sanchez, Gary").update(:prospect => true)
#@players_table.filter(:name => "Frazier, Clint").update(:prospect => true)
#@players_table.filter(:name => "Soler, Jorge").update(:prospect => true)
#@players_table.filter(:name => "Singleton, Jonathan").update(:prospect => true)
#@players_table.filter(:name => "Moran, Colin").update(:prospect => true)
#@players_table.filter(:name => "McCullers Jr., Lance").update(:prospect => true)
#@players_table.filter(:name => "Biddle, Jesse").update(:prospect => true)
#@players_table.filter(:name => "Foltyniewicz, Mike").update(:prospect => true)
#@players_table.filter(:name => "Stroman, Marcus").update(:prospect => true)
#@players_table.filter(:name => "Odorizzi, Jake").update(:prospect => true)
#@players_table.filter(:name => "Cecchini, Garin").update(:prospect => true)
#@players_table.filter(:name => "Wong, Kolten").update(:prospect => true)
#@players_table.filter(:name => "Odor, Rougned").update(:prospect => true)
#@players_table.filter(:name => "Sims, Lucas").update(:prospect => true)
#@players_table.filter(:name => "Swihart, Blake").update(:prospect => true)
#@players_table.filter(:name => "Betts, Mookie").update(:prospect => true)
#@players_table.filter(:name => "Lee, Zach").update(:prospect => true)
#@players_table.filter(:name => "Urias, Julio").update(:prospect => true)
#@players_table.filter(:name => "Marisnick, Jake").update(:prospect => true)
#@players_table.filter(:name => "DeShields Jr., Delino").update(:prospect => true)
#@players_table.filter(:name => "Hanson, Alen").update(:prospect => true)
#@players_table.filter(:name => "Rodriguez, Eduardo").update(:prospect => true)
#@players_table.filter(:name => "Cole, A.J.").update(:prospect => true)
#@players_table.filter(:name => "Johnson, Erik").update(:prospect => true)
#@players_table.filter(:name => "Dahl, David").update(:prospect => true)
#@players_table.filter(:name => "Choice, Michael").update(:prospect => true)
#@players_table.filter(:name => "Bauer, Trevor").update(:prospect => true)
#@players_table.filter(:name => "Bell, Josh").update(:prospect => true)
#@players_table.filter(:name => "Williams, Mason").update(:prospect => true)
#@players_table.filter(:name => "Sardinas, Luis").update(:prospect => true)
#@players_table.filter(:name => "Owings, Chris").update(:prospect => true)
#@players_table.filter(:name => "Wisler, Matt").update(:prospect => true)
#@players_table.filter(:name => "Shipley, Braden").update(:prospect => true)
#@players_table.filter(:name => "Davidson, Matt").update(:prospect => true)
#@players_table.filter(:name => "Nicolino, Justin").update(:prospect => true)
#@players_table.filter(:name => "Bethancourt, Christian").update(:prospect => true)
#@players_table.filter(:name => "Nelson, Jimmy").update(:prospect => true)
#@players_table.filter(:name => "Hak-Lee, Ju").update(:prospect => true)
#@players_table.filter(:name => "Montero, Rafael").update(:prospect => true)
#@players_table.filter(:name => "Barnes, Matt").update(:prospect => true)
#@players_table.filter(:name => "Kelly, Casey").update(:prospect => true)
#@players_table.filter(:name => "Peterson, D.J.").update(:prospect => true)
#@players_table.filter(:name => "Alcantara, Arismendy").update(:prospect => true)
#@players_table.filter(:name => "Berrios, J.O.").update(:prospect => true)
#@players_table.filter(:name => "Bonifacio, Jorge").update(:prospect => true)
#@players_table.filter(:name => "Gallo, Joey").update(:prospect => true)
#@players_table.filter(:name => "Osuna, Roberto").update(:prospect => true)
#@players_table.filter(:name => "Guerrieri, Taylor").update(:prospect => true)
#@players_table.filter(:name => "Escobar, Edwin").update(:prospect => true)
#@players_table.filter(:name => "Ball, Trey").update(:prospect => true)
#@players_table.filter(:name => "Ray, Robbie").update(:prospect => true)
#@players_table.filter(:name => "Piscotty, Stephen").update(:prospect => true)
#@players_table.filter(:name => "Herrera, Rosell").update(:prospect => true)
#@players_table.filter(:name => "Johnson, Pierce").update(:prospect => true)
