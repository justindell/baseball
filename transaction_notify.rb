#!/usr/bin/env ruby

require 'rubygems'
require 'mechanize'
require 'nokogiri'
require 'mail'

def send_email diff
  mail = Mail.new do
    from 'dell.justin@gmail.com'
    to 'dell.justin@gmail.com'
    subject '[BASEBALL] New transaction'
    body "New transaction in the IL league (http://baseball.fantasysports.yahoo.com/b1/15907):\n#{diff}"
  end 
  mail.delivery_method :smtp, { :address => "smtp.gmail.com",
                                :port => 587,
                                :domain => 'dell.justin',
                                :user_name => 'dell.justin@gmail.com',
                                :password => 'Payton34',
                                :authentication => 'plain',
                                :enable_starttls_auto => true }
  mail.deliver
end

agent = Mechanize.new
login = agent.get('https://login.yahoo.com/config/login')
login.form['login'] = 'chicagofan84'
login.form['passwd'] = 'Payton34'
agent.submit(login.form, login.form.button)

league = agent.get('http://baseball.fantasysports.yahoo.com/b1/15907')
doc = Nokogiri::HTML(league.body)

`cp transactions.html transactions.html.bak`
File.open('transactions.html', 'w+'){|f| f << doc.search('#recenttransactions table').to_html}
diff = `diff transactions.html transactions.html.bak`
send_email(diff) unless diff == ""
`rm transactions.html.bak`
