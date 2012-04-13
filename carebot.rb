require 'cinch'
require 'open-uri'
require 'nokogiri'
require 'cgi'
require 'rubygems'
require 'action_view'
require 'json'
require 'highline/import'

include ActionView::Helpers::DateHelper

def init_irc
  config = Hash.new
  config[:port]    = 6667
  config[:nick]    = "carebot"
  config[:use_ssl] = false

  [:server, :username, :password, :nick, :channels, :port, :use_ssl].each do |opt|

    if opt == :password
      value = ask("Enter password:\n>> ") { |q| q.echo = "*" }
    elsif opt == :channels
      vals = ask("Enter channels (comma separated):\n>> ")

      value = vals.split(",").collect{|a| "##{a.strip.gsub("#","")}"}
    else
      value = ask("Enter #{opt.to_s}#{config[opt].blank? ? '' : " (default: #{config[opt]})"}:\n>> ")
    end

    unless value.blank?
      config[opt] = value
    end
  end

  config
end

bot = Cinch::Bot.new do
  @@config = init_irc

  configure do |c|
    c.server   = @@config[:server].to_s
    c.nick     = @@config[:nick].to_s
    c.password = @@config[:password].to_s
    c.channels = @@config[:channels]
    c.port     = @@config[:port]
    c.user     = @@config[:username].to_s
    c.ssl.use  = @@config[:use_ssl]
  end

  helpers do
    @@url_list = {}
    @@countoff_list = {}
    @@countoff_info = ""

    def google(query)
      url = "http://www.google.com/search?q=#{CGI.escape(query)}"
      res = Nokogiri::HTML(open(url)).at("h3.r")

      title = res.text
      link = res.at('a')[:href]
      desc = res.at("./following::div").children.first.text
    rescue
      "No results found"
    else
      CGI.unescape_html("#{title} - #{desc} .... ") + " ( #{link} )"
    end

    def urban_dict(query)
      url = "http://www.urbandictionary.com/define.php?term=#{CGI.escape(query)}"
      CGI.unescape_html Nokogiri::HTML(open(url)).at("div.definition").text.gsub(/\s+/, ' ') rescue nil
    end

    def google_image(query)
      res = nil
      url = "http://www.google.com.ph/search?q=#{CGI.escape(query)}&um=1&ie=UTF-8&hl=en&tbm=isch&source=og"
      arr = Nokogiri::HTML(open(url)).search("div#ires").search("a")


      arr.each do |a|
        img = a.children.detect{|b| b.name == "img"}

        if img
          res = a
          break
        end
      end

      link = res.attributes["href"].value.split("&")[0].split("=")[1]
    rescue
      "No results found"
    else
      "#{link}"
    end

    def xkcd
      url = "http://dynamic.xkcd.com/random/comic/"
      res = Nokogiri::HTML(open(url)).search("div.s").search("img")[1]

      title = res[:title]
      link  = res[:src]
    rescue
      "No results found"
    else
      "#{title} - #{link}"
    end

    def gag9
      url = "http://9gag.com/random"
      res = Nokogiri::HTML(open(url))

      title = res.at("meta[property='og:title']").attributes["content"].value
      link  = res.at("meta[property='og:url']").attributes["content"].value
    rescue
      "No results found"
    else
      "#{title} - #{link}"
    end

    def toast
      url = "http://eatthattoast.com/?randomcomic"
      res = Nokogiri::HTML(open(url))

      title = res.at("div#comic-foot").at("a").text
      link  = res.at("div#comic-foot").at("a")[:href]
    rescue
      "No results found"
    else
      "#{title} - #{link}"
    end

    def youtube(query)
      url = "http://www.youtube.com/results?search_query=#{CGI.escape(query)}"
      res = Nokogiri::HTML(open(url)).at("a.yt-uix-tile-link")

      title = res.text
      link = "http://youtube.com#{res.attributes["href"].value}"
    rescue
      "No results found"
    else
      "#{title} - #{link} "
    end

    def twitter(query)
      url = "http://mobile.twitter.com/support/status/#{query}"
      res = Nokogiri::HTML(open(url))

      desc  = res.at("span.status").text
      title = res.at("strong").text
    rescue
      "No results found"
    else
      "Tweet by @#{title}: #{desc} "

    end

    def simsimi(q)
      query = URI.escape(q, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))

      query = query.gsub("%20", "%2520")

      url = "http://simsimi.com/func/req?lc=en&msg=#{query}"
      text = Nokogiri::HTML(open(url)).at("body").text

      says = JSON.parse(text)["sentence_resp"]

      if says.blank?
        says = ":)"
      end

      says
    end

    def summarize_countoff
      string = []
      count = 0
      @@countoff_list.each do |key, value|
        unless value.nil?
          count += value[:count].to_i
          string << "#{value[:nick]}-#{value[:count]}"
        end
      end

      unless string.blank?
        "#{@@countoff_info}: " + string.join(", ") + " .. TOTAL: #{count}"
      end
    end

    def countoff(query,ip)
      user = {}
      reply = ""
      nick = ip.split("@")[0]

      user[:nick] = nick

      if query.split(" ")[0].strip.to_i > 0
        count = query.split(" ")[0].strip.to_i

        if count <= 10
          user[:count] = count
          @@countoff_list[nick] = user

          reply = summarize_countoff
        else
          reply = "Nice try, #{nick}."
        end
      else
        reply = "#{nick}: use format: !count <number>"
      end

      reply
    end

    def add_to_count(query)
      #format !add_count <count>-<nick>@<ip>

      query.split(",").each do |q|
        q = q.strip
        count = q.split("-")[1]
        ip    = q.split("-")[0]

        countoff(count, ip)
      end
    end

    def update_countoff_info(query)
      @@countoff_info = query
    end

    def remove_countoff_user(user)
      @@countoff_list[user] = nil
    end

    def link_info(query, user, get_info=false)
      desc = ""
      urls = URI.extract(query, "http") + URI.extract(query, "https")

      unless urls.empty?
        url = urls.first

        if get_info || url =~ /youtube.com\/watch?/ || url =~ /vimeo.com\//
          res = Nokogiri::HTML(open(url)).at("title")

          desc = "#{res.text.gsub("\n","").strip}. " unless res.nil?
        end

        if @@url_list[url].blank?
          @@url_list[url] = {:user => user, :time => Time.now}
        else
          found = @@url_list[url]

          usr = found[:user] == user ? "You" : user
          desc += "#{usr} shared that link #{distance_of_time_in_words(found[:time], Time.now)} ago."
        end
      end

      desc
    end

  end

  on :message, "!commands" do |m, query|
    m.reply("queries: !google !g !youtube !y !urban !u !images !gis !twitter !t !link_info !count\nfun: !xkcd !9gag !toast\n\nOR you can PM me and we'll talk about life! :) ")
  end

  on :message, /!g (.+)/ do |m, query|
    m.reply google(query), true
  end

  on :message, /!gis (.+)/ do |m, query|
    m.reply google_image(query), true
  end

  on :message, /!google (.+)/ do |m, query|
    m.reply google(query), true
  end

  on :message, /!images (.+)/ do |m, query|
    m.reply google_image(query), true
  end

  on :message, /!y (.+)/ do |m, query|
    m.reply youtube(query), true
  end

  on :message, /!youtube (.+)/ do |m, query|
    m.reply youtube(query), true
  end

  on :message, /!u (.+)/ do |m, query|
    m.reply(urban_dict(query) || "No results found", true)
  end

  on :message, /!urban (.+)/ do |m, query|
    m.reply(urban_dict(query) || "No results found", true)
  end

  on :channel, /!xkcd/ do |m|
    m.reply(xkcd, true)
  end

  on :channel, /!9gag/ do |m|
    m.reply(gag9, true)
  end

  on :channel, /!toast/ do |m|
    m.reply(toast, true)
  end

  on :channel, /!count_info/ do |m|
    m.reply(summarize_countoff)
  end

  on :message, /!t (.+)/ do |m, query|
    m.reply(twitter(query), true)
  end

  on :message, /!twitter (.+)/ do |m, query|
    m.reply(twitter(query), true)
  end

  on :message, /!link_info (.+)/ do |m, query|
    reply = link_info(query, m.user.nick, true)
    m.reply(reply, true) unless reply.blank?
  end

  on :message, /!count (.+)/ do |m, query|
    ip = m.raw.split("!")[1].split(" ")[0]
    reply = countoff(query, ip)
    m.reply(reply) unless reply.blank?
  end

  on :message, /!add_count (.+)/ do |m, query|
    add_to_count(query) if m.user.nick == @cconfig[:username]
    m.reply(summarize_countoff)
  end

  on :message, /!update_countoff_info (.+)/ do |m, query|
    if m.user.nick == @@config[:username]
      reply = update_countoff_info(query)
      m.reply("countoff info updated") unless reply.blank?
    else
      m.reply "you don't have enough privileges to do this."
    end
  end

  on :channel, /!count_reset/ do |m|
    @@countoff_list = {} if m.user.nick == @@config[:username]
    m.reply("count reset")
  end

  on :message, /!remove_countoff_user (.+)/ do |m, query|
    remove_countoff_user(query) if m.user.nick == @@config[:username]
    m.reply("removed user on count")
  end

  on :message do |m|
    if m.channel.nil? && /carebot/ =~ m.params.first
      m.reply simsimi(m.params.last)
    end
  end

  on :channel do |m|
    if m.message =~ /http:\/\// || m.message =~ /https:\/\//
      reply = link_info(m.message, m.user.nick)
      m.reply(reply, true) unless reply.blank?
    end
  end
end

@@url_list = Hash.new

bot.start


