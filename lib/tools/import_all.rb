#!script/runner
# One script to import all data from remote sources.
# * Github: users per category
# * Last.fm: users with the same username + real name as on github
# * Last.fm: artists per user
# * Last.fm: tags per artist

require 'open-uri'

PAGES_PER_LANGUAGE=1
LANGUAGES = %w[Ruby PHP C Perl].map{|language| Language.find_or_create_by_name(language)}
ARTISTS_PER_USER=10
TAGS_PER_ARTIST=5

# == Github: users per category
LANGUAGES.each do |language|
  puts "=== Language: #{language.name}"
  1.upto(PAGES_PER_LANGUAGE).each do |page|
    begin
      repo_data = YAML.load(open("http://github.com/api/v2/yaml/repos/search/%25?language=#{language.name}&start_page=#{page}").read)
    rescue OpenURI::HTTPError => e
      puts e.inspect
      sleep 1
      retry
    end
    repo_data["repositories"].reject{|rdata| GithubUser.find_by_username(rdata["username"])}.each do |repo|
      github_user = GithubUser.find_or_initialize_by_username(repo["username"])
      if github_user.new_record?
        puts github_user.username
        retries = 0
        begin
          user_data = YAML.load(open("http://github.com/api/v2/yaml/user/show/#{github_user.username}").read)["user"]
        rescue OpenURI::HTTPError => e
          puts e.inspect
          puts "http://github.com/api/v2/yaml/user/show/#{github_user.username}"
          sleep 1
          retries += 1
          retry if retries <= 2
          next
        end
        unless user_data["type"]=="User"
          next 
        end
        github_user.real_name = user_data["name"]
        github_user.followers = user_data["followers_count"]
        github_user.save!
      end
      github_user.languages << language
    end
  end
end

# == Last.fm: users with the same username + real name as on github
GithubUser.all.each do |github_user|
  lastfm_user = LastfmUser.find_or_initialize_by_username(github_user.username)
  next unless lastfm_user.new_record?
  puts "=== Github user: #{github_user.username}"
  begin
    scrobbler_user = Scrobbler::User.new :name=>lastfm_user.username
    # scrobbler_user.load_info
  rescue => e
    # This is the best way we have to determine if a last.fm user exists: try to load their profile. The scrobbler gem raises an error when it does not.
    puts "!! No profile for #{scrobbler_user.username}."
    next
  else
    # lastfm_user.age = scrobbler_user.age
    # lastfm_user.country = scrobbler_user.country
    lastfm_user.real_name = scrobbler_user.realname
  end
  lastfm_user.verified = (lastfm_user.real_name == github_user.real_name)
  lastfm_user.save!

  # == Last.fm: artists per user
  scrobbler_user.top_artists[0...ARTISTS_PER_USER].each do |lastfm_artist|
    artist = Artist.find_or_initialize_by_name(lastfm_artist.name)
    if artist.new_record?
      puts "== Artist: #{artist.name}"
      # There appears to be a bug which always fetches the smallest image. Manually fix it to a larger one.
      artist.image_url = lastfm_artist.image(:large).sub '/34/', '/126/'
      artist.lastfm_url = lastfm_artist.url
      artist.image_url = lastfm_artist.image
      artist.save!
      # == Last.fm: tags per artist
      lastfm_artist.top_tags[0...TAGS_PER_ARTIST].each do |lastfm_tag|
        tag = Tag.find_or_create_by_name(lastfm_tag.name)
        if tag.new_record?
          tag.save!
        end
        artist.tags << tag
      end
    end
    lastfm_user.artists << artist
  end
end
