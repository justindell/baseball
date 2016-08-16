require 'rglpk'
require 'csv'

@players = []
@stacks = []
CSV.open('pitchers.csv', headers: true, header_converters: :symbol).each { |row| @players << row.to_hash }
CSV.open('hitters.csv', headers: true, header_converters: :symbol).each { |row| @players << row.to_hash }
@draftkings = CSV.open('draftkings.csv', headers: true, header_converters: :downcase).map { |row| row.to_hash }
@players.select { |p| p[:pos] != 'SP' }.group_by { |p| p[:team] }.each { |_, p| @stacks += p.combination(3).to_a.sort_by { |s| s.inject(0) { |acc,p| acc += p[:fpts].to_f } }.take(25) }

puts @stacks.count

def create_new_lineup(lineups)
  problem = Rglpk::Problem.new
  problem.name = 'optimal lineup generator'
  problem.obj.dir = Rglpk::GLP_MAX
  zero_stacks = @stacks.map { 0 }
  zero_players = @players.map { 0 }

  rows = problem.add_rows(9)
  matrix = []

  %w(C 1B 2B 3B SS).each_with_index do |position, i|
    rows[i].name = position
    rows[i].set_bounds(Rglpk::GLP_FX, 1, 1)
    matrix += @players.map { |p| p[:pos] == position ? 1 : 0 } + zero_stacks.dup
  end

  rows[5].name = 'P'
  rows[5].set_bounds(Rglpk::GLP_FX, 2, 2)
  matrix += @players.map { |p| p[:pos] == 'SP' ? 1 : 0 } + zero_stacks.dup

  rows[6].name = 'OF'
  rows[6].set_bounds(Rglpk::GLP_FX, 3, 3)
  matrix += @players.map { |p| p[:pos] == 'OF' ? 1 : 0 } + zero_stacks.dup

  rows[7].name = 'Salary'
  rows[7].set_bounds(Rglpk::GLP_DB, 0, 50000)
  matrix += @players.map { |p| p[:salary].to_i } + zero_stacks.dup

  rows[8].name = 'Team Size'
  rows[8].set_bounds(Rglpk::GLP_FX, 10, 10)
  matrix += @players.map { 1 } + zero_stacks.dup

  rows = problem.add_rows(@stacks.count)
  @stacks.each_with_index do |stack, i|
    rows[i].name = "Stack #{i}"
    rows[i].set_bounds(Rglpk::GLP_LO, 0, 0)
    player_line = zero_players.dup
    stack_line = zero_stacks.dup
    stack.each { |p| player_line[@players.find_index { |i| i == p }] = 1/3.0 }
    stack_line[i] = -1
    matrix += player_line + stack_line
  end

  rows = problem.add_rows(1)
  rows[0].name = "One Stack"
  rows[0].set_bounds(Rglpk::GLP_LO, 1, 1)
  matrix += zero_players.dup + @stacks.map { 1 }

  if lineups.count > 0
    rows = problem.add_rows(lineups.count)
    lineups.each_with_index do |lineup, i|
      rows[i].name = "Overlap #{i}"
      rows[i].set_bounds(Rglpk::GLP_DB, 0, 6)
      matrix += lineup.take(@players.count) + zero_stacks.dup
    end
  end

  pitchers = @players.select { |p| p[:pos] == 'SP' }
  rows = problem.add_rows(pitchers.count)
  pitchers.each_with_index do |pitcher, i|
    rows[i].name = pitcher[:team]
    rows[i].set_bounds(Rglpk::GLP_DB, 0, 5)
    matrix += @players.map { |p| p == pitcher ? 5 : (p[:position] != 'SP' && pitcher[:team] == p[:opp] ? 1 : 0) } + zero_stacks.dup
  end

  cols = problem.add_cols(@players.count + @stacks.count)
  cols.each do |c|
    c.set_bounds(Rglpk::GLP_DB, 0, 1)
    c.kind = Rglpk::GLP_IV
  end

  problem.obj.coefs = @players.map { |p| p[:fpts].to_f } + zero_stacks.dup

  problem.set_matrix(matrix)

  problem.mip(presolve: Rglpk::GLP_ON)
  score = problem.obj.mip
  return score, problem.cols.map { |c| c.mip_val }
end

def print_lineup(lineup, score)
  puts
  puts "SCORE: #{score}"
  puts "POS\tSALARY\tTEAM\tOPP\tPOINTS\tPLAYER"
  lineup.each_with_index do |solution, i|
    puts "#{@players[i][:pos]}\t#{@players[i][:salary]}\t#{@players[i][:team]}\t#{@players[i][:opp]}\t#{@players[i][:fpts]}\t#{@players[i][:player]}" if solution == 1 && i < @players.count
  end
end

lineups = []
score, lineup = create_new_lineup(lineups)
lineups << lineup
print_lineup(lineup, score)
score, lineup = create_new_lineup(lineups)
lineups << lineup
print_lineup(lineup, score)
score, lineup = create_new_lineup(lineups)
lineups << lineup
print_lineup(lineup, score)
score, lineup = create_new_lineup(lineups)
lineups << lineup
print_lineup(lineup, score)
score, lineup = create_new_lineup(lineups)
lineups << lineup
print_lineup(lineup, score)

def lookup_fanduel_id(team, position)
  team.select { |p| p[:pos] == position }.map do |p|
    fd = @fanduel.find { |f| "#{f['first name']} #{f['last name']}" == p[:player] }
    raise p.inspect unless fd
    fd['id']
  end
end

def lookup_draftkings_id(team, position)
  team.select { |p| p[:pos] == position }.map do |p|
    dk = @draftkings.find { |f| f[' name'] == p[:player] }
    raise p.inspect unless dk
    dk[' id']
  end
end

file = File.open('output.csv', 'w+')
file << %w(P P C 1B 2B 3B SS OF OF OF).join(',')
file << "\n"
lineups.each do |lineup|
  team = []
  lineup.each_with_index do |solution, i|
    team << @players[i] if solution == 1 && i < @players.count
  end
  file << %w(SP C 1B 2B 3B SS OF).map { |pos| lookup_draftkings_id(team, pos) }.flatten.join(',')
  file << "\n"
end
