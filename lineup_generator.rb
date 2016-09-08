require 'rglpk'
require 'csv'
require 'mechanize'

SITE = 'draftkings'
NUM_LINEUPS = 15
STACK_SIZE = 4
LINEUP_OVERLAP = 5
INDIVIDUAL_OVERLAP = 11
INCLUDED_TEAMS = %w()
EXCLUDED_TEAMS = %w()

SITE_MAP = { 'fanduel'    => { team_size: 9,
                               max_stack: 4,
                               num_pitchers: 1,
                               pitcher: 'P',
                               csv_header: %w(P C 1B 2B 3B SS OF OF OF),
                               salary: 35000,
                               id: lambda { |team, position| lookup_fanduel_id(team, position) } },
             'draftkings' => { team_size: 10,
                               max_stack: 5,
                               num_pitchers: 2,
                               pitcher: 'SP',
                               csv_header: %w(P P C 1B 2B 3B SS OF OF OF) ,
                               salary: 50000,
                               id: lambda { |team, position| lookup_draftkings_id(team, position) } } }
@players = []
@stacks = []
@config = SITE_MAP[SITE]
@salaries = CSV.open(SITE + '.csv', headers: true, header_converters: :downcase).map { |row| row.to_hash }

def lookup_fanduel_id(team, position)
  team.select { |p| p[:pos] == position }.map do |p|
    fd = @salaries.find { |f| "#{f['first name']} #{f['last name']}" == p[:player] }
    raise p.inspect unless fd
    fd['id']
  end
end

def lookup_draftkings_id(team, position)
  team.select { |p| p[:pos] == position }.map do |p|
    dk = @salaries.find { |f| f[' name'] == p[:player] }
    raise p.inspect unless dk
    dk[' id']
  end
end

def parse_csv body
  CSV.parse(body, headers: true, header_converters: :symbol).each do |row|
    #fd = @salaries.find { |f| "#{f['first name']} #{f['last name']}" == row[:name] }
    fd = @salaries.find { |f| f[' name'] == row[:name] }
    if fd
      row = row.to_hash
      row[:player] = row[:name]
      row[:fpts] = row[SITE.to_sym]
      row[:salary] = (fd['salary'] || fd[' salary']).to_f
      row[:team] = fd['team'] || fd['teamabbrev '].upcase
      row[:opp] = (fd['opponent'] || fd['gameinfo'].split(' ').first.gsub(fd['teamabbrev '], '').gsub('@', '')).upcase
      row[:pos] = fd['position'] || 'P'
      @players << row
    end
  end
end

agent = Mechanize.new

form = agent.get('http://www.fangraphs.com/dailyprojections.aspx?pos=all&stats=pit&type=sabersim&team=0&lg=all&players=0').forms.first
form['__EVENTTARGET'] = 'DFSBoard1$cmdCSV'
form['__EVENTARGUMENT'] = ''
parse_csv form.submit.body[3..-1]

form = agent.get('http://www.fangraphs.com/dailyprojections.aspx?pos=all&stats=bat&type=sabersim&team=0&lg=all&players=0').forms.first
form['__EVENTTARGET'] = 'DFSBoard1$cmdCSV'
form['__EVENTARGUMENT'] = ''
parse_csv form.submit.body[3..-1]

@players = @players.select { |p| p[:salary].to_f > 0 }
@players = @players.select { |p| INCLUDED_TEAMS.include?(p[:team]) } unless INCLUDED_TEAMS.empty?
@players = @players.select { |p| !EXCLUDED_TEAMS.include?(p[:team]) } unless EXCLUDED_TEAMS.empty?
@players = @players.sort_by { |p| p[:fpts].to_f }.reverse.take(250)
@players.select { |p| p[:pos] != @config[:pitcher] }.group_by { |p| p[:team] }.each { |_, p| @stacks += p.combination(STACK_SIZE).to_a.sort_by { |s| s.inject(0) { |acc,p| acc += p[:fpts].to_f } }.reverse.take(15) }
@stacks = @stacks.sort_by { |s| s.inject(0) { |acc,p| acc += p[:fpts].to_f } }.reverse.take(120)
@zero_stacks = @stacks.map { 0 }
@zero_players = @players.map { 0 }

def create_new_lineup(lineups)
  problem = Rglpk::Problem.new
  problem.name = 'optimal lineup generator'
  problem.obj.dir = Rglpk::GLP_MAX
  matrix = []

  rows = problem.add_rows(9)
  %w(C 1B 2B 3B SS).each_with_index do |position, i|
    rows[i].name = position
    rows[i].set_bounds(Rglpk::GLP_FX, 1, 1)
    matrix += @players.map { |p| p[:pos] == position ? 1 : 0 } + @zero_stacks.dup
  end

  rows[5].name = 'P'
  rows[5].set_bounds(Rglpk::GLP_FX, @config[:num_pitchers], @config[:num_pitchers])
  matrix += @players.map { |p| p[:pos] == @config[:pitcher] ? 1 : 0 } + @zero_stacks.dup

  rows[6].name = 'OF'
  rows[6].set_bounds(Rglpk::GLP_FX, 3, 3)
  matrix += @players.map { |p| p[:pos] == 'OF' ? 1 : 0 } + @zero_stacks.dup

  rows[7].name = 'Salary'
  rows[7].set_bounds(Rglpk::GLP_DB, @config[:salary] - 500, @config[:salary])
  matrix += @players.map { |p| p[:salary].to_i } + @zero_stacks.dup

  rows[8].name = 'Team Size'
  rows[8].set_bounds(Rglpk::GLP_FX, @config[:team_size], @config[:team_size])
  matrix += @players.map { 1 } + @zero_stacks.dup

  rows = problem.add_rows(@stacks.count)
  @stacks.each_with_index do |stack, i|
    rows[i].name = "Stack #{i}"
    rows[i].set_bounds(Rglpk::GLP_LO, 0, 0)
    player_line = @zero_players.dup
    stack_line = @zero_stacks.dup
    stack.each { |p| player_line[@players.find_index { |i| i == p }] = 1/STACK_SIZE.to_f }
    stack_line[i] = -1
    matrix += player_line + stack_line
  end

  rows = problem.add_rows(1)
  rows[0].name = "One Stack"
  rows[0].set_bounds(Rglpk::GLP_LO, 1, 1)
  matrix += @zero_players.dup + @stacks.map { 1 }

  if lineups.count > 0
    rows = problem.add_rows(lineups.count)
    lineups.each_with_index do |lineup, i|
      rows[i].name = "Overlap #{i}"
      rows[i].set_bounds(Rglpk::GLP_DB, 0, LINEUP_OVERLAP)
      matrix += lineup + @zero_stacks.dup
    end

    rows = problem.add_rows(1)
    rows[0].name = "Individual Overlap"
    rows[0].set_bounds(Rglpk::GLP_DB, 0, INDIVIDUAL_OVERLAP)
    @players.count.times do |i|
      matrix << lineups.map { |lineup| lineup[i] }.inject(&:+)
    end
    matrix += @zero_stacks.dup
  end

  pitchers = @players.select { |p| p[:pos] == @config[:pitcher] }
  rows = problem.add_rows(pitchers.count)
  pitchers.each_with_index do |pitcher, i|
    rows[i].name = pitcher[:team]
    rows[i].set_bounds(Rglpk::GLP_DB, 0, @config[:max_stack])
    matrix += @players.map { |p| p == pitcher ? @config[:max_stack] : (pitcher[:team] == p[:opp] ? 1 : 0) } + @zero_stacks.dup
  end

  cols = problem.add_cols(@players.count + @stacks.count)
  cols.each do |c|
    c.set_bounds(Rglpk::GLP_DB, 0, 1)
    c.kind = Rglpk::GLP_IV
  end

  problem.obj.coefs = @players.map { |p| p[:fpts].to_f } + @zero_stacks.dup

  problem.set_matrix(matrix)

  problem.mip(presolve: Rglpk::GLP_ON)
  score = problem.obj.mip
  return score, problem.cols.map { |c| c.mip_val }.take(@players.count)
end

def print_lineup(lineup, score)
  puts
  players = []
  lineup.each_with_index do |solution, i|
    players << @players[i] if solution == 1
  end
  freq = players.inject(Hash.new(0)) { |h,v| h[v[:team]] += 1; h }
  puts "STACK: #{players.max_by { |i| freq[i[:team]] }[:team]}"
  puts "POS\tSALARY\tTEAM\tOPP\tPOINTS\tPLAYER"
  %w(SP C 1B 2B 3B SS OF).map do |pos|
    players.select { |p| p[:pos] == pos }.sort_by { |p| p[:player] }.each do |p|
      puts "#{p[:pos]}\t#{p[:salary]}\t#{p[:team]}\t#{p[:opp]}\t#{p[:fpts]}\t#{p[:player]}"
    end
  end
end

lineups = []
NUM_LINEUPS.times do
  score, lineup = create_new_lineup(lineups)
  lineups << lineup
  print_lineup(lineup, score)
end

file = File.open('output.csv', 'w+')
file << @config[:csv_header].join(',')
file << "\n"
lineups.each do |lineup|
  team = []
  lineup.each_with_index do |solution, i|
    team << @players[i] if solution == 1
  end
  file << @config[:id].call(team, @config[:pitcher]).flatten.join(',') + ',' + %w(C 1B 2B 3B SS OF).map { |pos| @config[:id].call(team, pos) }.flatten.join(',')
  file << "\n"
end
