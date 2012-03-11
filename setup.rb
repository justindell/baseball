require 'rubygems'
require 'sequel'
require 'csv'

DB = Sequel.sqlite('baseball.sqlite')

puts "Creating players table"
DB.drop_table :players if DB.table_exists? :players
DB.create_table :players do
  primary_key :id
  String :name
  String :team
  String :position
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
  Decimal :whip
  Decimal :value
  Decimal :yahoo_value
  TrueClass :drafted, :default => false
  TrueClass :list_of_twelve, :default => false
  TrueClass :sleeper, :default => false
  TrueClass :injury, :default => false
  TrueClass :favorite, :default => false
  TrueClass :prospect, :default => false
end

DB.add_index :players, :id
@players_table = DB[:players]

puts "Calculating stats"
def std_dev values
  count = values.size
  mean = values.inject(:+) / count.to_f
  Math.sqrt( values.inject(0) { |sum, e| sum + (e - mean) ** 2 } / count.to_f )
end

def parse_csv categories, type
  players = {}
  csv_file = type == :batters ? 'batter_projections.csv' : 'pitcher_projections.csv'
  CSV.open(csv_file, {:headers => true, :header_converters => :downcase}).each do |row|
    players[row['player']] = {'pos' => row['pos'], 'team' => row['team'], 'value' => 0}
    categories.each{|c| players[row['player']][c] = row[c.downcase].to_f}
    ['era', 'whip'].each {|p| players[row['player']][p] *= -1 } if type == :pitchers
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

categories = ['r', 'hr', 'rbi', 'sb', 'avg', 'obp']
players = parse_csv categories, :batters
categories.each {|stat| calculate players, stat}
players.each do |name, player|
  @players_table.insert :name => name,
                 :team => player['team'],
                 :value => player['value'],
                 :r => player['r'],
                 :hr => player['hr'],
                 :rbi => player['rbi'],
                 :sb => player['sb'],
                 :avg => player['avg'],
                 :obp => player['obp'],
                 :position => player['pos']
end

categories = ['w', 'k', 's', 'era', 'whip']
players = parse_csv categories, :pitchers
categories.each {|stat| calculate players, stat}
players.each do |name, player|
  @players_table.insert :name => name,
                 :team => player['team'],
                 :value => player['value'],
                 :w => player['w'],
                 :k => player['k'],
                 :s => player['s'],
                 :era => player['era'],
                 :whip => player['whip'],
                 :position => 'P'
end


puts "Updating drafted players"
@players_table.filter(:name => [ 'Freddie Freeman', 'Jordan Zimmermann', 'Ian Kinsler', 'Brian Wilson', 'Jacoby Ellsbury',
'Matt Kemp', 'Jose Reyes', 'Andrew McCutchen', 'Jose Bautista', 'Desmond Jennings', 'Madison Bumgarner', 'James Shields',
'Mat Latos', 'Carlos Gonzalez', 'Mike Napoli', 'Rafael Betancourt', 'Brett Lawrie', 'Michael Cuddyer', 'Stephen Strasburg',
'Craig Kimbrel', 'Giancarlo Stanton', 'Eric Hosmer', 'Chris Young', 'Mark Trumbo', 'Josh Hamilton', 'Adrian Beltre',
'Pablo Sandoval', 'Dan Uggla', 'Ian Kennedy', 'C.J. Wilson', 'Curtis Granderson', 'Carlos Santana', 'Elvis Andrus',
'Matt Cain', 'Prince Fielder', 'Hunter Pence', 'Tim Lincecum', 'Neftali Feliz', 'Robinson Cano', 'Starlin Castro',
'David Price', 'Adam Wainwright', 'David Freese', 'J.J. Putz', 'Ryan Madson']).update(:drafted => true)

puts "Updating yahoo values"
@players_table.update(:yahoo_value => -1)
CSV.open('yahoo_values.csv', {:headers => true, :header_converters => :downcase}).each do |row|
  @players_table.filter(:name => row['player']).update(:yahoo_value => row['value'].to_i)
end
