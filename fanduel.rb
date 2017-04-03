#!/usr/bin/env ruby

require 'rglpk'
require 'csv'
require 'optparse'
require 'sequel'

CSV_HEADER = %w(P C 1B 2B 3B SS OF OF OF)
STACK_SIZE = 4
MAX_SALARY = 35000
DB = Sequel.connect("postgres://cfbdfs:#{ENV['CFBDFS_DATABASE_PASSWORD']}@54.69.133.42:5432/cbbdfs?search_path=mlb")

@config = { num_lineups: 25, lineup_overlap: 4, individual_overlap: 15, min_salary: MAX_SALARY - 500 }

def get_salaries(filename)
  salaries = []
  CSV.open(filename, headers: true, header_converters: :downcase).each do |row|
    next if row[:injury_indicator] == 'DL'
    salaries << row.to_h
  end
  salaries
end

def get_players(salaries)
  players = DB[:projections].all
  players.each do |player|
    salary = salaries.find { |salary| salary['nickname'] == player[:player_name] }
    if salary
      player[:salary] = salary['salary']
      player[:team] = salary['team']
      player[:opponent] = salary['opponent']
      player[:position] = salary['position']
      player[:id] = salary['id']
      player[:fdpts] = player[:fdpts].to_f
    end
  end
  players.delete_if { |p| p[:salary].nil? }
end

def get_stacks(players)
  stacks = []
  players.select { |p| p[:position] != 'P' }.group_by { |p| p[:team] }.each { |_, p| stacks += p.combination(STACK_SIZE).to_a.sort_by { |s| s.inject(0) { |acc,p| acc += p[:fdpts] } }.reverse.take(5) }
  stacks.sort_by { |s| s.inject(0) { |acc,p| acc += p[:fdpts].to_f } }.reverse.take(100)
end

def create_new_lineup(lineups, players, stacks)
  problem = Rglpk::Problem.new
  problem.name = 'optimal lineup generator'
  problem.obj.dir = Rglpk::GLP_MAX
  matrix = []

  rows = problem.add_rows(8)
  %w(P C 1B 2B 3B SS).each_with_index do |position, i|
    rows[i].name = position
    rows[i].set_bounds(Rglpk::GLP_FX, 1, 1)
    matrix += players.map { |p| p[:position] == position ? 1 : 0 } + Array.new(stacks.count, 0)
  end
  rows[6].name = 'OF'
  rows[6].set_bounds(Rglpk::GLP_FX, 3, 3)
  matrix += players.map { |p| p[:position] == 'OF' ? 1 : 0 } + Array.new(stacks.count, 0)
  rows[7].name = 'Salary'
  rows[7].set_bounds(Rglpk::GLP_DB, @config[:min_salary], MAX_SALARY)
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
  rows[0].name = "One Stack"
  rows[0].set_bounds(Rglpk::GLP_FX, 1, 1)
  matrix += Array.new(players.count, 0) + stacks.map { 1 }

  #if lineups.count > 0
    #rows = problem.add_rows(lineups.count)
    #lineups.each_with_index do |lineup, i|
      #rows[i].name = "Overlap #{i}"
      #rows[i].set_bounds(Rglpk::GLP_DB, 0, LINEUP_OVERLAP)
      #matrix += lineup + @Array.new(stacks.count, 0)
    #end

    #rows = problem.add_rows(1)
    #rows[0].name = "Individual Overlap"
    #rows[0].set_bounds(Rglpk::GLP_DB, 0, INDIVIDUAL_OVERLAP)
    #@players.count.times do |i|
      #matrix << lineups.map { |lineup| lineup[i] }.inject(&:+)
    #end
    #matrix += @Array.new(stacks.count, 0)
  #end

  pitchers = players.select { |p| p[:position] == 'P' }
  rows = problem.add_rows(pitchers.count)
  pitchers.each_with_index do |pitcher, i|
    rows[i].name = "Pitcher vs #{pitcher[:team]}"
    rows[i].set_bounds(Rglpk::GLP_DB, 0, STACK_SIZE)
    matrix += players.map { |p| p == pitcher ? STACK_SIZE : (pitcher[:team] == p[:opponent] ? 1 : 0) } + Array.new(stacks.count, 0)
  end

  cols = problem.add_cols(players.count + stacks.count)
  cols.each do |c|
    c.set_bounds(Rglpk::GLP_DB, 0, 1)
    c.kind = Rglpk::GLP_IV
  end

  puts "matrix: #{matrix.count}"
  puts "columns: #{players.count + stacks.count}"
  puts "rows: #{matrix.count / (players.count + stacks.count)}"

  problem.obj.coefs = players.map { |p| p[:fdpts] } + Array.new(stacks.count, 0)
  problem.set_matrix(matrix)
  problem.mip(presolve: Rglpk::GLP_ON)
  score = problem.obj.mip
  return score, problem.cols.map { |c| c.mip_val }.take(players.count)
end

def print_lineup(lineup, score, players)
  puts lineup.inspect
  team = []
  lineup.each_with_index { |solution, i| team << players[i] if solution == 1 }
  freq = team.inject(Hash.new(0)) { |h,v| h[v[:team]] += 1; h }
  puts "STACK: #{team.max_by { |i| freq[i[:team]] }[:team]}"
  puts "POS\tSALARY\tTEAM\tOPP\tPOINTS\tPLAYER"
  %w(P C 1B 2B 3B SS OF).map do |pos|
    team.select { |p| p[:position] == pos }.sort_by { |p| p[:player_name] }.each do |p|
      puts "#{p[:position]}\t#{p[:salary]}\t#{p[:team]}\t#{p[:opponent]}\t#{p[:fdpts].round(2)}\t#{p[:player_name]}"
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
    opts.parse!
  end

  salaries = get_salaries(ARGV.shift)
  players = get_players(salaries)
  stacks = get_stacks(players)

  score, lineup = create_new_lineup([], players, stacks)
  print_lineup(lineup, score, players)
end
