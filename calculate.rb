require 'sequel'

class Calculate
  DB = Sequel.sqlite('baseball.sqlite')

  class << self
    def players opts = {}
      query = DB[:players].filter('median_value > 0')
      query = query.filter(Sequel.like(:position, "%#{opts['position'].upcase}%")) if opts['position']
      query = opts['limit'] ? query.limit(opts['limit']) : query.limit(500)
      query = query.filter(:drafted => false) if opts['hide-drafted']
      query.all
    end

    def batters opts = {}
      query = DB[:players].exclude(:position => 'SP').exclude(:position => 'RP').filter('median_value > 0')
      query = query.filter(Sequel.like(:position, "%#{opts['position'].upcase}%")) if opts['position']
      query = opts['limit'] ? (!opts['limit'].empty? ? query.limit(opts['limit']) : query.limit(20)) : query.limit(500)
      query = query.filter(:drafted => false) if opts['hide-drafted']
      query.all
    end

    def pitchers opts = {}
      query = DB[:players].filter(Sequel.like(:position, "%P")).filter('bp_value > 0 or zips_value > 0 or steamer_value > 0')
      query = query.filter(position: opts['position'].upcase) if opts['position']
      query = opts['limit'] && !opts['limit'].empty? ? query.limit(opts['limit']) : query.limit(500)
      query = query.filter(:drafted => false) if opts['hide-drafted']
      query.all
    end

    def team
      DB[:players].filter(:mine => true).all
    end

    def draft player_id
      DB[:players].filter(:id => player_id).update(:drafted => true)
    end
  end
end
