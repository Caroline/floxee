class Person < CouchRest::ExtendedDocument
  use_database CouchRest.database!(Floxee.server)
  
  include CouchRest::Validation
  
  #save_callback :before, :generate_slug_from_name
  save_callback :before, :fetch_info
  save_callback :after, :fetch_stats
  save_callback :after, :fetch_latest_statuses
  
  unique_id do |contact|
    # TODO: Make this a recursive method to guarantee uniqueness
    contact.generate_unique_id
  end
  
  property :title
  property :first_name
  property :middle_name
  property :last_name
  property :nickname
  property :name_suffix
  property :gender
  property :email
  property :website
  property :phone
  property :fax
  
  # twitter api properties
  property :name
  property :screen_name
  property :location
  property :description
  property :profile_image_url
  property :url
  property :protected
  property :followers_count
  property :profile_background_color
  property :profile_text_color
  property :profile_link_color
  property :profile_sidebar_fill_color
  property :profile_sidebar_border_color
  property :friends_count
  property :favourites_count
  property :utc_offset
  property :statuses_count
  
  timestamps!
  
  validates_present :first_name, :last_name
  
  view_by :id, :descending => true
  view_by :screen_name
  view_by :last_name
  
  
  def display_name
    "#{self.first_name} #{self.last_name}"
  end
  
  def id_ordinal
    self.id.gsub(self.display_name.to_url,"").gsub("-", "").to_i
  end
  
  def tweets?
    not self.screen_name.blank?
  end
  
  def stats
     TwitterUserStats.by_screen_name(:key => self.screen_name).first
  end

  def fetch_info
    unless self.screen_name.nil?
      begin
        user = JSON.parse(Net::HTTP.get(URI.parse("http://twitter.com/users/show/#{self.screen_name}.json")))
        self.merge!(user) if user
      rescue
        puts "Problem getting Twitter info for #{self.display_name}"
      end
    end
  end
  
  def fetch_stats
    unless self.screen_name.nil?
      begin
      stats = TwitterUserStats.by_screen_name(:key => self.screen_name).first
        if stats
          stats.destroy
        else
          stats = TwitterUserStats.new
          stats.screen_name = self.screen_name
        end
        stats.save
      rescue
        puts "Problem getting TwitterCounter stats for #{self.display_name}"
      end
    end
  end
  
  def statuses
    TwitterStatus.by_from_user(:key => self.screen_name)
  end
  
  def fetch_latest_statuses
    unless self.screen_name.nil?
      begin
        if self.statuses.blank?
          # self.statuses = []
          # multiple calls to get all statuses
          page_count = (self.statuses_count/100) + 1
          (1..(page_count)).each do |page|
            search = Twitter::Search.new.from(self.screen_name).page(page).per_page(100).fetch()
            #self.statuses.concat search['results']
            search['results'].each do |tweet|
              ts = TwitterStatus.new(tweet)
              ts.person_id = self.id
              ts.save
            end
          end      
        else
          last_id = self.statuses.map{|status| status.id}.max
          search = Twitter::Search.new.from(self.screen_name).since(last_id).fetch()
          #self.statuses.concat(search['results']).uniq!      
          search['results'].each do |tweet|
            ts = TwitterStatus.new(tweet)
            ts.person_id = self.id
            ts.save
          end
        end
        # Refresh the TwitterStatus cache if new results are returned
        TwitterStatus.cached_by_id(true) if search['results'].size > 0
      rescue
        puts "Problem getting tweets for #{self.display_name}"
      end
    end
  end
  
  def self.paginate(options={})
    options[:sort] ||= 'last_name'
    
    options[:per_page] ||= 10
    options[:page] ||= 1
     
    options[:per_page] = options[:per_page].to_i
    options[:page] = options[:page].to_i
    
    if %w{statuses_count followers_count}.include?(options[:sort])
      @people = Person.search(options).sort_by{|p| p[options[:sort]].to_i}
    else
      @people = Person.search(options).sort_by{|p| p[options[:sort]].to_s}
    end
    @people.reverse! unless (options[:reverse].to_s == "true" or options[:reverse].blank?)
    @people.paginate(:page => options[:page], :per_page => options[:per_page])
  end
  
  def self.search(options={})
    @people = Rails.cache.fetch('people', :expires_in => 60*60*6) {Person.all}
    @people = @people.select{|p| p.display_name.downcase.include?(options[:q]) } unless options[:q].blank?
    @people
  end
  
  def self.most_followers_last_seven_days
    people_with_stats =  Person.all.select{|p| !p.stats.nil?}
    people_with_stats.sort_by{|p| p.stats.followers_change_last_seven_days.to_i}.reverse[0..9].map{|p| [p, p.stats.followers_change_last_seven_days]}
  end
  
  def self.most_followers_last_thirty_days
    people_with_stats =  Person.all.select{|p| !p.stats.nil?}
    people_with_stats.sort_by{|p| p.stats.followers_change_last_thirty_days.to_i}.reverse[0..9].map{|p| [p, p.stats.followers_change_last_thirty_days]}
  end

  def generate_unique_id
    unique_id = self.display_name.to_url
    people = Person.all.select {|person| person.id.include?(unique_id)}
    if people.empty?
      unique_id
    else
      max_ordinal = people.map {|person| person.id_ordinal}.max
      unique_id + "-" + (max_ordinal + 1).to_s
    end
  end
  
end