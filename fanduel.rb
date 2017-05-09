#!/usr/bin/env ruby

require 'rglpk'
require 'csv'
require 'optparse'
require 'sequel'

CSV_HEADER = %w(P C 1B 2B 3B SS OF OF OF)
STACK_SIZE = 3
TEAM_MAX = 4
MAX_BAT_ORDER = 6
FANDUEL_MAX_SALARY = 35000
YAHOO_MAX_SALARY = 200
EXCLUDE_TEAMS = %w()
DB = Sequel.connect("postgres://cfbdfs:#{ENV['CFBDFS_DATABASE_PASSWORD']}@54.69.133.42:5432/cbbdfs?search_path=mlb")

@config = { num_lineups: 25, lineup_overlap: 4, individual_overlap: 15 }

def translate_name(salary)
  name = @config[:yahoo] ? "#{salary['first name']} #{salary['last name']}" : salary['nickname']
  name = name.downcase.gsub('jr.', '').gsub('sr.', '').strip
  return 'gregory bird' if name == 'greg bird'
  return 'steve souza' if name == 'steven souza'
  return 'michael fiers' if name == 'mike fiers'
  return 'timothy anderson' if name == 'tim anderson'
  return 'hyun-soo kim' if name == 'hyun soo kim'
  return 'yulieski gurriel' if name == 'yuli gurriel'
  return 'manuel pina' if name == 'manny pina'
  name
end

def get_fanduel_salaries(filename)
  salaries = []
  CSV.open(filename, headers: true, header_converters: :downcase).each do |row|
    next if row['injury_indicator'] == 'DL'
    next if EXCLUDE_TEAMS.include?(row['team'])
    salaries << row.to_h
  end
  salaries
end

def get_yahoo_salaries(filename)
  salaries = []
  salaries = []
  CSV.open(filename, headers: true, header_converters: :downcase).each do |row|
    next if row['injury_indicator'] =~ /DL/
    next if EXCLUDE_TEAMS.include?(row['team'])
    salaries << row.to_h
  end
  salaries
end

def get_salaries(filename)
  if @config[:yahoo]
    get_yahoo_salaries(filename)
  else
    get_fanduel_salaries(filename)
  end
end

def get_nathan_players(salaries)
  players = DB[:projections].where(game_date: Date.today).all
  salaries.each do |salary|
    player = players.find { |player| translate_name(salary) == player[:player_name].downcase }
    if player
      player[:salary] = salary['salary'].to_i
      player[:team] = salary['team']
      player[:opponent] = salary['opponent']
      player[:position] = salary['position']
      player[:id] = salary['id']
      player[:fpts] = player[:fanduel_points].to_f
    elsif @config[:debug] && salary['batting order'] != '0' && salary['batting order'] != ''
      puts "could not find salary for " + (salary['nickname'] || "#{salary['first name']} #{salary['last name']}")
    end
  end
  players.delete_if { |p| p[:salary].nil? || (p[:position] != 'P' && p[:bat_order] > MAX_BAT_ORDER) } # TODO: keep lower bats if high value?
end

def get_dfn_players(salaries)
  rows, players = [], []
  Dir[@config[:daily_fantasy_nerd] + '/DFN*'].each do |file|
    CSV.open(file, headers: true, header_converters: :downcase).each { |row| rows << row }
  end
  salaries.each do |salary|
    salary['nickname'] = 'Nick Castellanos' if salary['nickname'] == 'Nicholas Castellanos'
    player = rows.find { |row| salary['nickname'].downcase.gsub(' jr.', '') == row['player name'].downcase }
    if player
      players << { player_name: player['player name'],
                   salary: salary['salary'],
                   team: salary['team'],
                   opponent: salary['opponent'],
                   position: salary['position'],
                   id: salary['id'],
                   bat_order: salary['batting order'].to_i,
                   fpts: player['proj fp'].to_f }
    elsif @config[:debug] && salary['batting order'] != '0' && salary['batting order'] != ''
      puts "could not find projection for #{salary['nickname']}"
    end
  end
  players.delete_if { |p| p[:salary].nil? || (p[:position] != 'P' && p[:bat_order] > MAX_BAT_ORDER) } # TODO: keep lower bats if high value?
end

def get_players(salaries)
  if @config[:daily_fantasy_nerd]
    get_dfn_players(salaries)
  else
    get_nathan_players(salaries)
  end
end

def get_stacks(players)
  stacks = []
  players.select { |p| p[:position] != 'P' }.group_by { |p| p[:team] }.each { |_, p| stacks += p.combination(STACK_SIZE).to_a.sort_by { |s| s.inject(0) { |acc,p| acc += p[:fpts] } }.reverse.take(5) }
  stacks.sort_by { |s| s.inject(0) { |acc,p| acc += p[:fpts].to_f } }.reverse.take(100)
end

def create_new_lineup(lineups, players, stacks)
  problem = Rglpk::Problem.new
  problem.name = 'optimal lineup generator'
  problem.obj.dir = Rglpk::GLP_MAX
  pitchers = players.select { |p| p[:position] == 'P' }
  matrix = []

  rows = problem.add_rows(8)
  %w(C 1B 2B 3B SS).each_with_index do |position, i|
    rows[i].name = position
    rows[i].set_bounds(Rglpk::GLP_FX, 1, 1)
    matrix += players.map { |p| p[:position] == position ? 1 : 0 } + Array.new(stacks.count, 0)
  end
  num_pitchers = @config[:yahoo] ? 2 : 1
  rows[5].name = 'P'
  rows[5].set_bounds(Rglpk::GLP_FX, num_pitchers, num_pitchers)
  matrix += players.map { |p| p[:position] == 'P' ? 1 : 0 } + Array.new(stacks.count, 0)
  rows[6].name = 'OF'
  rows[6].set_bounds(Rglpk::GLP_FX, 3, 3)
  matrix += players.map { |p| p[:position] == 'OF' ? 1 : 0 } + Array.new(stacks.count, 0)
  rows[7].name = 'Salary'
  rows[7].set_bounds(Rglpk::GLP_DB, @config[:min_salary], @config[:yahoo] ? YAHOO_MAX_SALARY : FANDUEL_MAX_SALARY)
  matrix += players.map { |p| p[:salary].to_i } + Array.new(stacks.count, 0)

  rows = problem.add_rows(stacks.count)
  stacks.each_with_index do |stack, i|
    rows[i].name = "Stack #{i}"
    rows[i].set_bounds(Rglpk::GLP_LO, 0, 0)
    player_line = Array.new(players.count, 0)
    stack_line = Array.new(stacks.count, 0)
    stack.each { |p| player_line[players.find_index { |i| i == p }] = 1/STACK_SIZE.to_f }
    stack_line[i] = -1
    matrix += player_line + stack_line
  end

  rows = problem.add_rows(1)
  rows[0].name = "Two Stacks"
  rows[0].set_bounds(Rglpk::GLP_FX, 2, 2)
  matrix += Array.new(players.count, 0) + stacks.map { 1 }

  rows = problem.add_rows(pitchers.count)
  pitchers.each_with_index do |pitcher, i|
    rows[i].name = "#{pitcher[:team]} Maximum"
    rows[i].set_bounds(Rglpk::GLP_DB, 0, TEAM_MAX)
    matrix += players.map { |p| (pitcher[:team] == p[:team] ? 1 : 0) } + Array.new(stacks.count, 0)
  end

  rows = problem.add_rows(pitchers.count)
  pitchers.each_with_index do |pitcher, i|
    rows[i].name = "Pitcher vs #{pitcher[:team]}"
    rows[i].set_bounds(Rglpk::GLP_DB, 0, STACK_SIZE)
    matrix += players.map { |p| p == pitcher ? STACK_SIZE : (pitcher[:team] == p[:opponent] ? 1 : 0) } + Array.new(stacks.count, 0)
  end

  if lineups.count > 0
    rows = problem.add_rows(lineups.count)
    lineups.each_with_index do |lineup, i|
      rows[i].name = "Overlap #{i}"
      rows[i].set_bounds(Rglpk::GLP_DB, 0, @config[:lineup_overlap])
      matrix += lineup + Array.new(stacks.count, 0)
    end

    rows = problem.add_rows(1)
    rows[0].name = "Individual Overlap"
    rows[0].set_bounds(Rglpk::GLP_DB, 0, @config[:individual_overlap])
    players.count.times do |i|
      matrix << lineups.map { |lineup| lineup[i] }.inject(&:+)
    end
    matrix += Array.new(stacks.count, 0)
  end

  cols = problem.add_cols(players.count + stacks.count)
  cols.each do |c|
    c.set_bounds(Rglpk::GLP_DB, 0, 1)
    c.kind = Rglpk::GLP_IV
  end

  if @config[:debug]
    puts "matrix: #{matrix.count}"
    puts "columns: #{players.count + stacks.count}"
    puts "rows: #{matrix.count / (players.count + stacks.count)}"
  end

  problem.obj.coefs = players.map { |p| p[:fpts] } + Array.new(stacks.count, 0)
  problem.set_matrix(matrix)
  problem.mip(presolve: Rglpk::GLP_ON)
  score = problem.obj.mip
  return score, problem.cols.map { |c| c.mip_val }.take(players.count)
end

def solution_to_team(lineup, players)
  [].tap do |team|
    lineup.each_with_index { |solution, i| team << players[i] if solution == 1 }
  end
end

def print_lineup(lineup, score, players)
  team = solution_to_team(lineup, players)
  freq = team.inject(Hash.new(0)) { |h,v| h[v[:team]] += 1; h }
  puts
  puts "STACKS: #{freq.select { |t,v| v > 2 }.keys.join(', ')}  TOTAL: #{team.inject(0) { |a, p| a + p[:fpts] }}" if @config[:debug]
  puts "POS\tSALARY\tTEAM\tOPP\tPOINTS\tPLAYER"
  %w(P C 1B 2B 3B SS OF).map do |pos|
    team.select { |p| p[:position] == pos }.sort_by { |p| p[:player_name] }.each do |p|
      puts "#{p[:position]}\t#{p[:salary]}\t#{p[:team]}\t#{p[:opponent]}\t#{p[:fpts].round(2)}\t#{p[:player_name]}"
    end
  end
end

def output_csv(lineups, players)
  File.open('output.csv', 'w+') do |file|
    file << CSV_HEADER.join(',') + "\n"
    lineups.each do |lineup|
      team = solution_to_team(lineup, players)
      file << CSV_HEADER.uniq.map do |header|
        team.select { |p| p[:position] == header }.map { |p| p[:id] }
      end.flatten.join(',') + "\n"
    end
  end
end

if __FILE__ == $0
  ARGV.options do |opts|
    opts.banner = 'Usage: lineup_generator.rb [options] <salary_csv>'
    opts.on('-n=x', '--num-lineups=x', Integer)        { |val| @config[:num_lineups] = val }
    opts.on('-o=x', '--lineup-overlap=x', Integer)     { |val| @config[:lineup_overlap] = val }
    opts.on('-i=x', '--individual-overlap=x', Integer) { |val| @config[:individual_overlap] = val }
    opts.on('-m=x', '--minimum-salary=x', Integer)     { |val| @config[:min_salary] = val }
    opts.on('-d=x', '--daily-fantasy-nerd=x')          { |val| @config[:daily_fantasy_nerd] = val }
    opts.on('-y',   '--yahoo')                         { |val| @config[:yahoo] = true }
    opts.on('--debug')                                 { |val| @config[:debug] = val }
    opts.parse!
  end

  @config[:min_salary] ||= @config[:yahoo] ? YAHOO_MAX_SALARY - 5 : FANDUEL_MAX_SALARY - 500

  salaries = get_salaries(ARGV.shift)
  players = get_players(salaries)
  stacks = get_stacks(players)

  lineups = []
  @config[:num_lineups].times do
    score, lineup = create_new_lineup(lineups, players, stacks)
    print_lineup(lineup, score, players)
    lineups << lineup
  end

  output_csv(lineups, players)
end
