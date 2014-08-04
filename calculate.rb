require 'sequel'

class Calculate
  DB = Sequel.sqlite('baseball.sqlite')

  class << self
    def players opts = {}
      query = DB[:players].order(:value).reverse
      query = query.filter(:position.like("%#{opts['position'].upcase}%")) if opts['position']
      query = opts['limit'] ? query.limit(opts['limit']) : query.limit(500)
      query = query.filter(:drafted => false) if opts['hide-drafted']
      query.all
    end

    def batters opts = {}
      query = DB[:players].exclude(:position => 'P').order(:value).reverse
      query = query.filter(:position.like("%#{opts['position'].upcase}%")) if opts['position']
      query = opts['limit'] ? (!opts['limit'].empty? ? query.limit(opts['limit']) : query.limit(20)) : query.limit(500)
      query = query.filter(:drafted => false) if opts['hide-drafted']
      query.all
    end

    def pitchers opts = {}
      query = DB[:players].filter(:position => 'P').order(:value).reverse
      query = opts['limit'] && !opts['limit'].empty? ? query.limit(opts['limit']) : query.limit(500)
      query = query.filter(:drafted => false) if opts['hide-drafted']
      query.all
    end

    def draft player_id
      puts "drafting #{player_id}"
      DB[:players].filter(:id => player_id).update(:drafted => true)
    end
  end
end
